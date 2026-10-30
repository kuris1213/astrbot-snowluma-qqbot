"""中文文字回复 + 日语语音回复。

AstrBot 自带的 TTS 只会把回复原文念出来，而这里的音色是日语音色：直接念中文会带
日语腔。本插件在发消息前把中文译文翻成日语，调本地 AnifLive-TTS 合成，然后把消息链
换成「语音 + 中文原文」。

依赖：本地 AnifLive-TTS 在 127.0.0.1:9882（见 D:\\gpt.sovit\\docs）。
"""
from __future__ import annotations

import hashlib
import random
import re
import time
from pathlib import Path

import aiohttp

from astrbot.api import AstrBotConfig, logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.message_components import Plain, Record
from astrbot.api.star import Context, Star, register

TRANSLATE_SYSTEM = (
    "你是中日翻译。把用户给的中文翻译成自然的日语口语，用于角色配音朗读。"
    "要求：保留原语气、情绪和口语感；不要翻译成书面语；"
    "不要解释、不要加引号或任何标记，只输出日语译文本身。"
)

KANA_RE = re.compile(r"[\u3040-\u30ff]")

# 命中这些特征就认为模型在自行合成语音
AUDIO_HINT_RE = re.compile(
    r"System\.Speech|SpeechSynthesizer|SelectVoice|Speak\(|edge-tts|pyttsx3|gtts|"
    r"espeak|say\.ps1|ncat\.exe|AudioSegment|soundfile\.write|scipy\.io\.wavfile\.write",
    re.IGNORECASE,
)

VOICE_RULE = (
    "\n\n【语音规则】你没有语音合成能力，也不需要自己合成语音。"
    "严禁使用 shell 或 Python 调用 System.Speech、SAPI、edge-tts、pyttsx3、"
    "ffmpeg 等工具生成任何音频文件，也严禁通过 send_message_to_user 发送你自己生成的音频文件。"
    "系统会自动把你的回复翻译成日语并用角色音色配音，你只需要正常用中文回复文字即可。"
    "如果用户要求语音，告诉他语音会自动附上，不要自己动手生成。"
)


@register(
    "astrbot_plugin_ja_voice",
    "local",
    "中文文本 + 日语语音：把回复翻译成日语后交给本地 AnifLive-TTS 合成",
    "1.0.0",
)
class JaVoicePlugin(Star):
    def __init__(self, context: Context, config: AstrBotConfig):
        super().__init__(context, config)
        self.enable = bool(getattr(config, "enable", True))
        self.tts_base = str(getattr(config, "tts_base", "http://127.0.0.1:9882/v1")).rstrip("/")
        self.model = str(getattr(config, "model", "kurisu-v2proplus"))
        self.voice = str(getattr(config, "voice_profile", "default"))
        self.language = str(getattr(config, "language", "ja"))
        self.probability = float(getattr(config, "probability", 1.0))
        self.keep_text = bool(getattr(config, "keep_text", True))
        self.timeout = float(getattr(config, "timeout", 120))
        self.block_shell_tools = bool(getattr(config, "block_shell_tools", False))
        self.rule_enabled = bool(getattr(config, "inject_voice_rule", True))
        self.block_self_tts = bool(getattr(config, "block_self_tts_commands", True))
        self.temp_dir = Path("data/temp")
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        self._cache: dict[str, str] = {}
        logger.info(
            f"[ja_voice] ready: enable={self.enable} tts={self.tts_base} "
            f"model={self.model} voice={self.voice} p={self.probability} "
            f"rule={self.rule_enabled} block_tools={self.block_shell_tools} "
            f"block_self_tts={self.block_self_tts}"
        )

    # ------------------------------------------------------- 给模型立规矩
    @filter.on_llm_request()
    async def inject_voice_rule(self, event: AstrMessageEvent, request):
        """阻止模型自己用 shell/python 合成音频。

        三层：
        1. 系统提示词里明确禁止（软约束）；
        2. 包装 shell / python 工具的 handler，凡是合成音频的命令直接拒绝（硬约束，只挡这一类）；
        3. 可选 block_shell_tools，把工具整个摘掉（最粗暴）。
        """
        if self.rule_enabled:
            try:
                request.system_prompt = (request.system_prompt or "") + VOICE_RULE
            except Exception as exc:  # noqa: BLE001
                logger.warning(f"[ja_voice] 注入语音规则失败: {exc}")

        tools = getattr(request, "func_tool", None)
        if tools is None:
            return

        if self.block_self_tts:
            for name in ("astrbot_execute_shell", "astrbot_execute_python"):
                try:
                    tool = tools.get_tool(name)
                except Exception:  # noqa: BLE001
                    tool = None
                if tool is not None:
                    self._guard_tool(tool)

        if self.block_shell_tools:
            for name in ("astrbot_execute_shell", "astrbot_execute_python"):
                try:
                    tools.remove_tool(name)
                except Exception:  # noqa: BLE001 - 工具不存在
                    pass

    @staticmethod
    def _guard_tool(tool) -> None:
        """给工具 handler 套一层：命中音频合成特征就直接拒绝执行。"""
        original = getattr(tool, "handler", None)
        if original is None or getattr(original, "_ja_voice_guarded", False):
            return

        async def guarded(*args, **kwargs):
            blob = repr(args) + repr(kwargs)
            if AUDIO_HINT_RE.search(blob):
                logger.warning("[ja_voice] 拦下模型自行合成语音的工具调用")
                return (
                    "已拒绝：不允许自行合成语音。语音会由系统自动生成并附在回复后面，"
                    "请直接用中文回答，不要重试这类命令。"
                )
            return await original(*args, **kwargs)

        guarded._ja_voice_guarded = True
        tool.handler = guarded

    # ------------------------------------------------------------------ 翻译
    async def _translate(self, event: AstrMessageEvent, text: str) -> str | None:
        key = hashlib.sha1(text.encode("utf-8")).hexdigest()
        cached = self._cache.get(key)
        if cached:
            logger.info("[ja_voice] 命中翻译缓存")
            return cached

        provider = await self.context.get_using_provider_async(umo=event.unified_msg_origin)
        if provider is None:
            logger.warning("[ja_voice] 没有可用的对话模型，跳过语音")
            return None

        try:
            response = await provider.text_chat(
                prompt=text,
                system_prompt=TRANSLATE_SYSTEM,
                contexts=[],
            )
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[ja_voice] 翻译失败: {type(exc).__name__}: {exc}")
            return None

        japanese = (getattr(response, "completion_text", "") or "").strip()
        japanese = japanese.strip("「」\"' \n")
        if not japanese:
            return None

        self._cache[key] = japanese
        if len(self._cache) > 256:
            for stale in list(self._cache)[:128]:
                self._cache.pop(stale, None)
        return japanese

    # ------------------------------------------------------------------ 合成
    async def _synthesize(self, japanese: str) -> Path | None:
        payload = {
            "model": self.model,
            "voice_profile": self.voice,
            "text": japanese,
            "language": self.language,
            "stream": False,
        }
        started = time.time()
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.tts_base}/audio/speech",
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=self.timeout),
                ) as response:
                    if response.status != 200:
                        body = (await response.text())[:200]
                        logger.error(f"[ja_voice] TTS 返回 {response.status}: {body}")
                        return None
                    audio = await response.read()
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[ja_voice] TTS 请求失败: {type(exc).__name__}: {exc}")
            return None

        if len(audio) < 1024:
            logger.error(f"[ja_voice] TTS 音频过短（{len(audio)} 字节），丢弃")
            return None

        path = self.temp_dir / f"ja_voice_{int(time.time() * 1000)}.wav"
        path.write_bytes(audio)
        logger.info(
            f"[ja_voice] 合成完成 {path.name} {len(audio) / 1024:.0f} KB "
            f"{time.time() - started:.2f}s | {japanese[:40]}"
        )
        return path

    # ------------------------------------------------------------------ 钩子
    @filter.on_decorating_result()
    async def decorate(self, event: AstrMessageEvent):
        if not self.enable:
            return

        result = event.get_result()
        if result is None or not result.chain:
            return
        if not result.is_llm_result():
            return
        if self.probability < 1.0 and random.random() > self.probability:
            return

        text = "".join(
            comp.text for comp in result.chain if isinstance(comp, Plain) and comp.text
        ).strip()
        if len(text) < 2:
            return
        # 已经是日语就不用再翻
        if KANA_RE.search(text) and not re.search(r"[\u4e00-\u9fff]", text):
            japanese = text
        else:
            japanese = await self._translate(event, text)
        if not japanese:
            return

        audio = await self._synthesize(japanese)
        if audio is None:
            return

        record = Record.fromFileSystem(str(audio))
        record.text = japanese
        chain = [record]
        if self.keep_text:
            chain.append(Plain(text))
        result.chain = chain

    async def terminate(self):
        self._cache.clear()
