# 快速开始

## Ubuntu 物理机 / systemd

这是当前唯一推荐的部署方式：开机启动、网页/API 常驻、CPU 默认 50%、用户活跃/工作时间/CPU 忙时自动停止计算。

支持 Ubuntu/Debian `amd64` 和 `arm64`。脚本会在当前机器上本地编译，所以 ARM 机器不需要预构建镜像。

缓存目录安装并启动。源码会放在 `~/.cache/veloxhash/source`：

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
- 普通用户执行：安装到 `~/.cache/veloxhash/runtime`，优先使用 `systemctl --user`，不可用时使用后台进程
- 普通用户有 sudo 且想安装系统服务：加 `--mode system`
- 普通用户无 sudo：加 `--mode user` 或直接默认执行

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

常用命令：

```bash
sudo veloxhash-mining status
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
