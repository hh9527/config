# config

个人配置仓库，目标路径为 `~/.config`。

## 一键安装

```bash
curl https://raw.githubusercontent.com/hh9527/config/refs/heads/main/install | bash
```

脚本会将仓库克隆或更新到 `~/.config`，然后执行：

```bash
~/.config/shell/setup.sh
```

`setup.sh` 会建立必要的 shell 启动入口，例如 bash 的 `~/.bashrc`、`~/.bash_profile`、`~/.profile`，以及 zsh 的 `~/.zshenv` 链接。
