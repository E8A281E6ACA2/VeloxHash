# 快速开始

## Ubuntu 物理机 / systemd

这是当前唯一推荐的部署方式：开机启动、网页/API 常驻、CPU 默认 50%、用户活跃/工作时间/CPU 忙时自动停止计算。

稳定支持 Ubuntu/Debian `amd64` 和 `arm64`。脚本会自动识别系统、CPU 架构、包管理器、安装模式和实际网页端口。优先下载当前架构的预编译 Release 包；没有对应包时会回退到本地编译。

当前正式推荐 Ubuntu/Debian。Fedora/RHEL、Arch、Alpine 的依赖安装属于尽力兼容；Alpine/musl 不能直接使用 glibc 预编译包，遇到时应走源码编译。

推荐使用预编译 Release 包安装。包会解压到 `~/.cache/veloxhash/source`：

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-release.sh | sudo bash -s -- --mode system <公开钱包地址>
```

用户模式，包括 root 用户也想安装到 `/root/.cache/veloxhash` 的情况：

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-release.sh | bash -s -- --mode user <公开钱包地址>
```

安装时直接指定矿池：

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-release.sh | bash -s -- --mode user --pool-url auto.c3pool.org:33333 --pool-password x --coin monero <公开钱包地址>
```

这条命令默认从 `8089` 开始找端口；如果 `8089` 被占用，会自动选择后面的可用端口，最多检查到 `8189`。安装完成输出里会显示实际端口和 token。

如果 Release 里没有当前架构的预编译包，脚本会回退到源码编译。也可以直接使用源码编译入口：

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-cache.sh | sudo bash -s -- --mode system <公开钱包地址>
```

手动缓存安装：

```bash
sudo apt-get update
sudo apt-get install -y git curl
mkdir -p ~/.cache/veloxhash
if [ -d ~/.cache/veloxhash/source/.git ]; then
  git -C ~/.cache/veloxhash/source pull --ff-only
else
  git clone https://github.com/E8A281E6ACA2/VeloxHash.git ~/.cache/veloxhash/source
fi
bash ~/.cache/veloxhash/source/scripts/bootstrap-cache-install.sh <公开钱包地址>
```

执行规则：

- root 执行：安装系统级 systemd 服务
- 普通用户执行：安装到 `~/.cache/veloxhash/runtime`，优先使用 `systemctl --user`，并自动尝试开启 linger 以支持重启后自启动；不可用时使用后台进程
- 普通用户有 sudo 且想安装系统服务：加 `--mode system`
- 普通用户无 sudo：加 `--mode user` 或直接默认执行
- 强制系统服务时必须是 systemd 主机；非 systemd 环境请用 `--mode user`

从 GitHub 手动拉取并启动：

```bash
git clone https://github.com/E8A281E6ACA2/VeloxHash.git
cd VeloxHash
sudo ./start-mining.sh <公开钱包地址>
```

手动安装方式：

```bash
cmake -S . -B build-veloxhash -DCMAKE_BUILD_TYPE=Release -DWITH_OPENCL=OFF -DWITH_CUDA=OFF
cmake --build build-veloxhash -j$(nproc)
sudo ./scripts/install-systemd-service.sh
sudo veloxhash-mining wallet set <公开钱包地址>
sudo veloxhash-status --short
```

也可以直接使用一键入口：

```bash
sudo ./start-mining.sh <公开钱包地址>
```

读取网页 token：

```bash
sudo veloxhash-mining token
```

网页地址：

```text
http://<server-ip>:8089/
```

默认端口是 `8089`。如果端口被占用，安装器会自动选择下一个可用端口。查看实际端口：

```bash
sudo sed -n 's/^VELOXHASH_HTTP_PORT=//p' /etc/veloxhash/veloxhash.env
```

通常不需要指定端口。安装时如果确实想指定首选端口，可以这样写；如果该端口被占用，仍会继续向后找：

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-release.sh | bash -s -- --mode user --http-port 8090 <公开钱包地址>
```

常用命令：

```bash
sudo veloxhash-mining status
sudo veloxhash-mining pool
sudo veloxhash-mining pool set auto.c3pool.org:33333 x monero
sudo veloxhash-policy status
sudo veloxhash-doctor
```

普通用户模式常用命令：

```bash
~/.cache/veloxhash/runtime/bin/veloxhash-user status
~/.cache/veloxhash/runtime/bin/veloxhash-user token
~/.cache/veloxhash/runtime/bin/veloxhash-user stop
~/.cache/veloxhash/runtime/bin/veloxhash-user start
```

如果普通用户模式安装后提示 `Boot startup: needs administrator`，管理员执行一次即可：

```bash
loginctl enable-linger <用户名>
```

这里只需要公开钱包地址，不导入私钥或助记词。

## 主副节点统计

```bash
sudo veloxhash-cluster init-primary
sudo veloxhash-cluster token
sudo veloxhash-cluster nodes
```

副节点加入：

```bash
sudo veloxhash-cluster join --primary-url http://<primary-ip>:8090 --token <cluster-token>
```

## 停止

```bash
sudo veloxhash-mining disable
```
