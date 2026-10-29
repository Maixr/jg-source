# 音效来源与授权

## 素材

**IgnisForge Free SFX Sampler**（43 个合成复古音效，取其中 15 个）
- 来源：https://opengameart.org/content/ignisforge-free-sfx-sampler-43-synthesized-retro-sound-effects
- 作者：IgnisForge（https://ignisforge.itch.io）
- 授权：**CC0 1.0（公有领域贡献）** —— 无需署名，可商用，无附加条件。
  这里署名只是出于礼貌，不是授权要求。

原始素材为 44100Hz / 16bit / 立体声 WAV。仓库里的这些文件都被
`tools/prepare_sfx.py` 处理过：去头尾静音、降采样到 22050Hz 单声道、
按事件需要做峰值归一化、截断到目标时长、加淡入淡出（防爆音）。
所以体积从 1.2MB 压到约 230KB。

## 事件对照

| 文件 | 原始素材 | 用途 |
|---|---|---|
| `ui_click.wav` | blip_01 | 按钮点击 |
| `ui_back.wav` | blip_05 | 取消 / 关闭 |
| `place.wav` | plasma_01 | 放下分身 |
| `upgrade.wav` | powerup_05 | 升级 / 重建小屋 |
| `remove.wav` | blip_10 | 移除分身 |
| `hit.wav` | hurt_01 | 敌人被打中（节流 55ms） |
| `die.wav` | hurt_15 | 敌人被击杀 |
| `leak.wav` | explosion_01 | 漏字（掉剧情完整度） |
| `wave.wav` | blip_15 | 新一波开始 |
| `win.wav` | jingle_01 | 通关 |
| `lose.wav` | stinger_01 | 失败 |
| `card.wav` | coin_05 | 新敌人卡片弹出 |
| `drawer.wav` | jump_05 | 养成抽屉开合 |
| `boss.wav` | stinger_04 | 首领「晦」登场 |
| `heal.wav` | spellzap_01 | 疗愈符治疗（节流 220ms） |

## 换音效

把同名 `.wav` 丢进本目录覆盖即可，代码不用改（`core/audio.gd` 按名字加载，
找不到就静默跳过）。想重新从原始素材生成：解压原包后跑

```powershell
python tools/prepare_sfx.py --src <解压目录> --out art/sfx
```

改事件和素材的对应关系，编辑 `tools/prepare_sfx.py` 顶部的 `EVENTS` 表。
