# Firefox

[English](Firefox.md) | 简体中文

`install.sh`（以及 `uu`）会配置本机每个 Firefox 安装的默认 profile。它管理两样东西：一个小的 `user.js` 和 oh-my-firefox 主题。

## Profiles

安装器读取 `~/Library/Application Support/Firefox/profiles.ini`，使用每个 `[Install…]` 段的 `Default=` profile，即每个已安装 Firefox 版本一个。没有安装使用的 profile 保持不变。指向 Firefox 文件夹之外的路径会被忽略。

## `user.js`

`config/firefox/user.js` 会以 `user.js` 链接到上述每个 profile。它的清单行使用 `firefox` 类型；目标路径相对于每个 profile，而不是 `$HOME`。

Firefox 每次启动都会读取 `user.js`，并覆盖 `about:config` 中的值。受管的设置：

| 设置 | 值 |
|---|---|
| `toolkit.legacyUserProfileCustomizations.stylesheets` | `true`；主题需要 |
| `font.*` | 正文使用 Rec Sans Mt.Baker，等宽使用 Rec Mono St.Helens，以及对应字号 |
| `privacy.fingerprintingProtection.overrides` | `-FontVisibilityLangPack`；否则指纹保护会让网页看不到 `~/Library/Fonts` 中的字体。其他保护仍然开启。Mozilla 针对个别网站的覆盖规则仍可能在这些网站上隐藏它们 |
| `browser.search.suggest.enabled`、`browser.urlbar.suggest.*` | `false`；不显示搜索、热门、赞助或常用网站建议 |
| `browser.newtabpage.*` | `false`；不显示新标签页、推荐内容或常用网站 |

要修改这些设置，请编辑 `config/firefox/user.js`；在 `about:config` 中的修改会在下次启动时被重置。其他设置（例如固定网站）仍由你在 `about:config` 中管理，永远不会存入这个公开仓库。

## oh-my-firefox 主题

profile 的 `chrome/` 文件夹是独立的公开仓库 [MOSconfig/oh-my-firefox](https://github.com/MOSconfig/oh-my-firefox)，包含 `userChrome.css` 和 `userContent.css`。dot-configs 不复制它。

对每个 profile，安装器会：

- `chrome/` 不存在时，把它克隆进去；
- `chrome/` 是干净的 oh-my-firefox 检出、位于有 upstream 的分支时，fast-forward 它；
- `chrome/` 不是 Git 检出、跟踪其他仓库，或有本地修改、本地提交、detached HEAD 时，保持不变并给出提示。

Git 从不提示输入，也从不 merge 或强制更新。设置 `DOT_CONFIGS_OH_MY_FIREFOX_URL` 可以从其他地址克隆。主题请在它自己的仓库中修改。

## 应用

运行 `uu` 或 `./install.sh` 后重启 Firefox。Firefox 只在启动时读取 `user.js` 和 `chrome/`。

## 检查

```sh
scripts/check.sh firefox
ls -l "$HOME/Library/Application Support/Firefox/Profiles"/*/user.js
git -C "$HOME/Library/Application Support/Firefox/Profiles/<profile>/chrome" status -sb
```
