# INFRA-002 · 稳定开发签名证书 LoocapDev · 证书重建路径

> 2026-10-12 实施。目的：消除每次重编译后录屏/麦克风 TCC 授权被清零的问题。
> 证书与私钥在 `~/.loocap-certs/`（**不在 git 仓内**，勿搬入）。

## 原理（为什么 adhoc 每次都要重新授权）

- adhoc 签名（`codesign --sign -`）：每次构建 cdhash 都变，macOS TCC 把产物当**新 App**，授权清零。
- 换成证书身份后，App 的 Designated Requirement（DR）= `identifier "com.voidzhang.audio-record-mac" and certificate root = H"a9ea33aa…"` —— DR 锚定**证书哈希**而非 cdhash。重编译只变 cdhash、不变证书 → DR 持续满足 → TCC 授权保留。
- 硬证据（2026-10-12 双轮构建）：两轮 cdhash 不同（`9f424460…` vs 前一轮），DR 逐字节相同。

## 当前证书

| 项 | 值 |
|---|---|
| CN / 身份名 | `LoocapDev`（O=Loocap Personal） |
| 有效期 | 2026-10-12 → 2036-10-09（10 年） |
| EKU | Code Signing |
| 私钥 | `~/.loocap-certs/LoocapDev.key`（本地，勿外传） |
| 备份 | `~/.loocap-certs/LoocapDev-legacy.p12`（导入密码 `loocap-dev-import`，**建议自行改密重导出并离线备份**） |

## 换机 / 证书过期后重建（两条路）

### 路 A：有备份（推荐）
```bash
# 双击 LoocapDev-legacy.p12 导入登录钥匙串（密码见上表），
# 或命令行：
security import ~/.loocap-certs/LoocapDev-legacy.p12 \
  -k ~/Library/Keychains/login.keychain-db -P loocap-dev-import -T /usr/bin/codesign
# 信任（代码签名策略）：
security add-trusted-cert -p codeSign \
  -k ~/Library/Keychains/login.keychain-db ~/.loocap-certs/LoocapDev.crt
# 验证：
security find-identity -v -p codesigning   # 应列出 "LoocapDev"
```

### 路 B：无备份（重新生成）
```bash
mkdir -p ~/.loocap-certs && cd ~/.loocap-certs
openssl req -newkey rsa:2048 -nodes -keyout LoocapDev.key -x509 -days 3650 \
  -out LoocapDev.crt -subj "/CN=LoocapDev/O=Loocap Personal" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "basicConstraints=critical,CA:FALSE"
openssl pkcs12 -export -legacy -out LoocapDev-legacy.p12 \
  -inkey LoocapDev.key -in LoocapDev.crt -passout pass:<新密码>
security import LoocapDev-legacy.p12 -k ~/Library/Keychains/login.keychain-db \
  -P <新密码> -T /usr/bin/codesign
security add-trusted-cert -p codeSign \
  -k ~/Library/Keychains/login.keychain-db LoocapDev.crt
```
⚠️ 路 B 会得到**新证书哈希** → TCC 视为新身份，需重新授权一次（仅此一次）。

## 坑位记录

1. **OpenSSL 3 默认 p12 算法 macOS 不认**（`SecKeychainItemImport: MAC verification failed`）→ 导出必须加 `-legacy`。
2. **`find-identity -p codesigning` 不列未信任证书** → 导入后必须 `add-trusted-cert -p codeSign`，否则 build-app.sh 检测不到身份会回退 adhoc。
3. 换签名身份后**首次启动**，TCC 会视为新 App 弹一次授权——这是最后一次授权，勾完即长期稳定。
4. 钥匙串里另有一枚公司 Developer ID（Tencent 88L2Q4487U）——个人 App **不要动用**，合规红线。
5. 构建脚本支持 `LOOCAP_SIGN_IDENTITY=xxx bash build-app.sh` 覆盖身份；身份缺失自动回退 adhoc 并告警。

## 验证方法（任何人可复跑）

```bash
codesign -dv --verbose=4 build/AudioRecordMac.app | grep Authority   # 应为 LoocapDev
codesign -d -r- build/AudioRecordMac.app | tail -1                   # DR 应含 certificate root = H"a9ea33aa…"
# 连续两次 build-app.sh，DR 应逐字节相同、CDHash 应不同
```
