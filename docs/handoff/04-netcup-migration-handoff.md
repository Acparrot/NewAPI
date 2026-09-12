# New API 迁移到 netcup VPS 交接文档

本文用于后续开新对话，把当前部署在腾讯云轻量应用服务器上的 New API 迁移到 netcup VPS。

## 1. 结论：这台 netcup VPS 是否可行

截图中的配置：

```text
2 vCore
4 GB DDR5 ECC 内存
美国 Manassas
128 GB NVMe
2.5 Gbit/s 接口
24 小时平均流量超过 2 TB 后临时限速到 200 Mbit/s
可扩展本地块存储
```

结论：可行，适合当前 New API 小规模使用。

理由：

```text
当前腾讯云服务器约 3.3 GiB 内存，New API + PostgreSQL + Redis + Caddy 已能运行
netcup 4 GB 内存略高于当前环境
128 GB NVMe 明显大于当前 40 GB 磁盘
2 vCore 足够中小规模 API 网关使用
2.5 Gbit/s 接口充裕
2 TB/24h 后限速 200 Mbit/s 对普通 API 中转通常够用
```

注意：

```text
如果未来高并发、大量日志、很多用户同时调用，2 vCore/4 GB 可能会吃紧
如果面向中国大陆用户，美国机房延迟会比腾讯云广州高
如果要在中国大陆合规运营，服务器迁到海外不等于无需合规，需要按实际业务咨询专业意见
```

## 2. 当前已知部署状态

当前服务：

```text
域名：https://api.jiatuc.cn
旧服务器：腾讯云轻量应用服务器
旧服务器公网 IPv4：159.75.88.72
系统：Ubuntu 22.04
部署目录：/opt/new-api
部署方式：Docker Compose
容器：new-api、postgres、redis、new-api-caddy
数据库：PostgreSQL
反向代理：Caddy 容器
```

当前本地资料：

```text
D:\NewAPI\deploy\tencent-lighthouse-install.sh
D:\NewAPI\docs\01-new-api-usage-maintenance-operations.md
D:\NewAPI\docs\02-new-api-deployment-retrospective.md
D:\NewAPI\docs\03-new-api-full-deployment-tutorial.md
```

不要在交接文档中记录：

```text
管理员密码
数据库密码
Redis 密码
SESSION_SECRET
CRYPTO_SECRET
上游 API Key
用户令牌
```

## 3. 推荐迁移策略

推荐使用“备份恢复迁移”，不要直接重装后手动重配。

迁移对象：

```text
PostgreSQL 数据库备份
/opt/new-api/.env
/opt/new-api/Caddyfile
/opt/new-api/docker-compose.yml
必要时迁移 /opt/new-api/logs
```

其中最重要的是：

```text
数据库备份
.env
```

`.env` 里包含数据库密码、Redis 密码和加密密钥。迁移到新服务器时应保持一致，否则已有加密数据可能无法解密。

## 4. 迁移前准备

在 netcup 新服务器上准备：

```text
Ubuntu 22.04 或 Debian 12
Docker
Docker Compose v2
开放防火墙 22/80/443
不要开放 3000/5432/6379
```

先不要立刻改 DNS。先用临时方式验证新服务器。

建议创建一个临时测试域名：

```text
newapi-test.jiatuc.cn -> netcup 新服务器 IP
```

如果不想创建测试域名，也可以先只验证容器和本机健康检查，最后再切换 `api.jiatuc.cn`。

## 5. 旧服务器备份命令

在旧服务器腾讯云终端执行：

```bash
cd /opt/new-api
sudo mkdir -p backups
sudo docker compose exec -T postgres pg_dump -U newapi -d new-api > backups/new-api-$(date +%F-%H%M%S).sql
sudo tar -czf backups/new-api-config-$(date +%F-%H%M%S).tar.gz .env Caddyfile docker-compose.yml
ls -lh backups
```

如果需要连同日志一起备份：

```bash
cd /opt/new-api
sudo tar -czf backups/new-api-logs-$(date +%F-%H%M%S).tar.gz logs
```

## 6. 传输到新服务器

从旧服务器传到新服务器可用：

```bash
scp /opt/new-api/backups/new-api-*.sql root@NEW_SERVER_IP:/root/
scp /opt/new-api/backups/new-api-config-*.tar.gz root@NEW_SERVER_IP:/root/
```

如果不能从旧服务器直连新服务器，也可以先下载到本地，再上传到新服务器。

## 7. 新服务器恢复步骤

在新服务器执行：

```bash
sudo mkdir -p /opt/new-api
sudo chown -R "$USER":"$USER" /opt/new-api
cd /opt/new-api
tar -xzf /root/new-api-config-*.tar.gz
sudo docker compose pull
sudo docker compose up -d postgres redis
```

等待数据库启动：

```bash
sudo docker compose ps
```

恢复数据库：

```bash
cd /opt/new-api
cat /root/new-api-*.sql | sudo docker compose exec -T postgres psql -U newapi -d new-api
```

启动全部服务：

```bash
sudo docker compose up -d
sudo docker compose ps
curl -i http://127.0.0.1:3000/api/status
```

## 8. DNS 切换

确认新服务器本机健康检查正常后，再切换 DNS：

```text
api.jiatuc.cn A 记录从旧服务器 IP 改为 netcup 新服务器 IP
```

切换后验证：

```bash
nslookup api.jiatuc.cn
curl -I https://api.jiatuc.cn
```

如果 HTTPS 证书尚未自动签发，查看：

```bash
cd /opt/new-api
sudo docker compose logs --tail=100 caddy
```

## 9. 回滚策略

切 DNS 前不要删除旧服务器。

如果新服务器异常：

```text
把 api.jiatuc.cn 的 A 记录改回 159.75.88.72
确认旧服务器容器仍在运行
继续使用旧服务器
```

建议新服务器稳定运行至少 3 到 7 天后，再考虑释放旧服务器。

## 10. 新对话提示词

可以在新对话中直接粘贴以下内容：

```text
我要把已经部署好的 New API 从腾讯云轻量应用服务器迁移到 netcup VPS。

当前旧环境：
- 域名：https://api.jiatuc.cn
- 旧服务器 IPv4：159.75.88.72
- 系统：Ubuntu 22.04
- 部署目录：/opt/new-api
- 部署方式：Docker Compose
- 服务：new-api + postgres + redis + caddy
- 数据库：PostgreSQL
- Caddy 容器负责 HTTPS
- 防火墙只开放 22/80/443，不开放 3000/5432/6379

新服务器：
- netcup VPS
- 2 vCore
- 4 GB DDR5 ECC RAM
- 128 GB NVMe
- 机房：美国 Manassas
- 计划安装 Ubuntu 22.04 或 Debian 12

我希望你一步一步带我迁移：
1. 先确认新服务器系统、Docker、Compose、防火墙
2. 从旧服务器备份 PostgreSQL 和 /opt/new-api 配置
3. 把备份传到新服务器
4. 在新服务器恢复数据库和配置
5. 先本机健康检查
6. 再切换 api.jiatuc.cn 的 DNS
7. 验证 HTTPS 和 New API 登录
8. 保留旧服务器作为回滚，稳定后再清理

请不要让我泄露密码、API Key、SESSION_SECRET、CRYPTO_SECRET 或用户令牌。如果需要敏感信息，优先让我在服务器终端本地执行命令。
```

## 11. 迁移完成判定

满足以下条件才算完成：

```text
新服务器 docker compose ps 全部正常
curl http://127.0.0.1:3000/api/status 正常
https://api.jiatuc.cn 可访问
管理员可登录
已有渠道、用户、令牌、设置仍存在
模型调用测试成功
旧服务器暂时保留，可回滚
```

