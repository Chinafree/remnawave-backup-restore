<p aling="center"><a href="https://github.com/distillium/remnawave-backup-restore">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="./media/logo.png" />
   <source media="(prefers-color-scheme: light)" srcset="./media/logo-black.png" />
   <img alt="Backup & Restore" src="https://github.com/distillium/remnawave-backup-restore" />
 </picture>
</a></p>

> [!CAUTION]
> **脚本会备份并恢复整个 remnawave 的目录和数据库，以及（可选...**[...]

<details>
<summary>🌌 主菜单预览</summary>

![screenshot](./media/preview.png)
</details>

## 功能：
- 交互式菜单
- 直接通过 Telegram 机器人或群组话题发送带有备份附件的通知
- 通知脚本的最新版本
- 将备份发送到 Google Drive（可选）
- 手动创建备份
- 设置定期自动备份
- 从备份恢复
- 更改配置
- 更新脚本
- 删除脚本
- 已实现备份保留策略（7 天）

## 迁移方法的补充说明：

<details>
  <summary>📝 仅面板：迁移到新服务器</summary>
  
- 在 Cloudflare 中将面板的子域名改为新的 IP 地址。以及其他服务的子域名（如果它们被[...]）
- 执行目录和数据库的恢复
- 如有需要，请自行恢���域名证书
- 访问链接和密码将是之前进行备份的旧面板的
- 删除所有节点上服务端口（默认 2222）的旧规则并创建新的。这是为了[...] 

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

- 你很棒！剩下的就是安装和配置其它你需要的服务（例如 kuma、beszel 等等）

</details>

<details>
  <summary>📝 面板+节点：迁移到新服务器</summary>
  
- 在 Cloudflare 中将面板和与面板位于同一台的“根”节点的子域名改为新的 IP 地址。[...]
- 如有需要，请自行恢复域名证书
- 执行目录和数据库的恢复
- 通过端口 8443 启用对面板的访问（来自 eGames 的脚本，选项「管理面板访问」）
- 访问链接和密码将是之前进行备份的旧面板的
- 在节点管理中找到与面板同一台的根节点。里面标有旧服务器的地址。接着[...]
- 现在以与打开时相同的方式关闭通过端口 8443 的面板访问
- 删除所有外部节点上服务端口（默认 2222）的旧规则并创建新的。这需要[...]

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

- 你很棒！剩下的就是安装和配置其它你需要的服务（例如 kuma、beszel 等等）

</details>

<details>
  <summary>📝 面板+节点：迁移为“仅面板”（在当前服务器上）</summary>
  
- 执行目录��数据库的恢复
- 访问链接和密码将是之前进行备份的旧面板的
- 从面板中删除旧的“根”节点以及与其关联的入站（inbound）和主机（host）
- 删除文件 `.env-node`（在面板服务器上），命令：
  
```bash
rm /opt/remnawave/.env-node
```

- 你很棒！剩下的就是安装和配置其它你需要的服务（例如 kuma、beszel 等等）

</details>

<details>
  <summary>📝 面板+节点：迁移为“仅面板”（在新服务器上）</summary>

- 在 Cloudflare 中将面板的子域名改为新的 IP 地址。以及其他服务的子域名（如果它们被[...]）
- 如有需要，请自行恢复域名证书
- 执行目录和数据库的恢复
- 访问链接和密码将是之前进行备份的旧面板的
- 从面板中删除旧的“根”节点以及与其关联的入站（inbound）和主机（host）
- 删除文件 `.env-node`（在面板服务器上），命令：
  
```bash
rm /opt/remnawave/.env-node
```

- 删除所有节点上服务端口（默认 2222）的旧规则并创建新的。这是为了[...]

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

- 你很棒！剩下的就是安装和配置其它你需要的服务（例如 kuma、beszel 等等）
  
</details>

## 安装（需要 root）:

```
curl -o ~/backup-restore.sh https://raw.githubusercontent.com/Chinafree/remnawave-backup-restore/main/backup-restore.sh && chmod +x ~/backup-restore.sh && ~/backup-restore.sh
```
## 命令:
- `rw-backup` — 从系统任何位置快速访问菜单

```
``` 
