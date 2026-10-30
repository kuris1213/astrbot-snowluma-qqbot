"""把 templates/ 下的脱敏配置渲染成本机可用的运行时配置。

由 deploy/install.ps1 调用，不直接面向用户。

用法：
  python render_config.py --repo <仓库根> --token <OneBot令牌> \
      --bot-qq <机器人QQ> --admin-qq <主人QQ> --deepseek-key <key> [--force]
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys

PLACEHOLDER_QQ = "YOUR_QQ_NUMBER"
PLACEHOLDER_UMO = "snowluma:FriendMessage:YOUR_QQ_NUMBER"
PLACEHOLDER_TOKEN = "REPLACE_WITH_RANDOM_ONEBOT_TOKEN"


def load(path: str):
    with open(path, encoding="utf-8-sig") as fh:
        return json.load(fh)


def save(path: str, data) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8-sig", newline="\n") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def replace_str(value: str, *, qq: str, token: str) -> str:
    return (
        value.replace(PLACEHOLDER_UMO, f"snowluma:FriendMessage:{qq}")
        .replace(PLACEHOLDER_QQ, qq)
        .replace(PLACEHOLDER_TOKEN, token)
    )


def walk_replace(node, *, qq: str, token: str):
    if isinstance(node, dict):
        return {k: walk_replace(v, qq=qq, token=token) for k, v in node.items()}
    if isinstance(node, list):
        return [walk_replace(v, qq=qq, token=token) for v in node]
    if isinstance(node, str):
        return replace_str(node, qq=qq, token=token)
    return node


def render_cmd_config(templates: str, data_dir: str, *, qq: str, token: str, deepseek_key: str) -> str:
    src = os.path.join(templates, "astrbot", "cmd_config.json")
    data = load(src)
    for source in data.get("provider_sources", []):
        if source.get("provider") == "deepseek":
            source["key"] = [deepseek_key] if deepseek_key else []
    admins = ["astrbot"]
    if qq and qq not in admins:
        admins.append(qq)
    data["admins_id"] = admins
    for platform in data.get("platform", []):
        if platform.get("type") == "aiocqhttp":
            platform["ws_reverse_token"] = token
    out = os.path.join(data_dir, "cmd_config.json")
    save(out, data)
    return out


def render_plugin_configs(templates: str, data_dir: str, *, qq: str, token: str, force: bool) -> int:
    src_dir = os.path.join(templates, "astrbot", "plugins")
    dst_dir = os.path.join(data_dir, "config")
    os.makedirs(dst_dir, exist_ok=True)
    count = 0
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith(".json"):
            continue
        dst = os.path.join(dst_dir, name)
        if os.path.exists(dst) and not force:
            continue
        data = load(os.path.join(src_dir, name))
        save(dst, walk_replace(data, qq=qq, token=token))
        count += 1
    return count


def render_snowluma(templates: str, snowluma_home: str, *, bot_qq: str, token: str, force: bool) -> None:
    if not snowluma_home or not os.path.isdir(snowluma_home):
        print(f"[skip] SnowLuma home not found: {snowluma_home or '(not configured)'}")
        return
    config_dir = os.path.join(snowluma_home, "config")
    os.makedirs(config_dir, exist_ok=True)

    def write(template_name: str, target_name: str) -> None:
        dst = os.path.join(config_dir, target_name)
        if os.path.exists(dst) and not force:
            print(f"[keep] {dst}")
            return
        data = load(os.path.join(templates, "snowluma", template_name))
        save(dst, walk_replace(data, qq=bot_qq, token=token))
        print(f"[write] {dst}")

    write("runtime.json", "runtime.json")
    write("onebot.json", "onebot.json")
    if bot_qq:
        write("onebot_account.json", f"onebot_{bot_qq}.json")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--astrbot-home", default="")
    parser.add_argument("--token", required=True)
    parser.add_argument("--bot-qq", default="")
    parser.add_argument("--admin-qq", required=True)
    parser.add_argument("--deepseek-key", default="")
    parser.add_argument("--snowluma-home", default="")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    templates = os.path.join(args.repo, "templates")
    astrbot_home = args.astrbot_home or os.path.join(args.repo, "astrbot")
    if not os.path.isabs(astrbot_home):
        astrbot_home = os.path.join(args.repo, astrbot_home)
    data_dir = os.path.join(astrbot_home, "data")

    cmd = render_cmd_config(
        templates,
        data_dir,
        qq=args.admin_qq,
        token=args.token,
        deepseek_key=args.deepseek_key,
    )
    print(f"[write] {cmd}")

    count = render_plugin_configs(
        templates,
        data_dir,
        qq=args.admin_qq,
        token=args.token,
        force=args.force,
    )
    print(f"[write] {count} plugin config(s)")

    render_snowluma(
        templates,
        args.snowluma_home,
        bot_qq=args.bot_qq,
        token=args.token,
        force=args.force,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
