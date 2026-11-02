## 下载哪个

### Android

| 文件 | 适用机型 |
| --- | --- |
| `app-arm64-v8a-release.apk` | 绝大多数手机（2018 年以后的机型都是 arm64） |
| `app-armeabi-v7a-release.apk` | 较老的 32 位设备 |
| `app-x86_64-release.apk` | 模拟器、x86 平板 |

下载对应 APK 直接安装即可。系统会提示「未知来源应用」，允许继续就行——这个应用没有上架任何应用商店，属于正常现象。

> **之前装过自己编译的 debug 版？** 必须先卸载再装。debug 与 release 签名不同，Android 会拒绝覆盖安装并报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。

### Windows

下载 `recipe-book-windows-x64.zip`，解压到任意**有写权限**的目录（别放 `C:\Program Files`），双击 `recipe_book.exe`。需要 Windows 10 1809 或更高版本。

## 数据存在哪

- **Android**：应用私有目录，卸载应用即一并删除
- **Windows**：`%APPDATA%\com.yg.recipe_book`；如果该目录不可写，会自动回退到 exe 同级的 `data_user` 目录

需要在设备之间迁移、或者想长期保存，用「设置 → 导出备份」生成 zip 文件，换设备后「恢复备份」即可（恢复完成后需要重启应用）。

## 全部功能离线

应用不含任何联网代码：无账号、无同步、无统计上报。数据只在这台设备的本地数据库里。
## 校验（可选）

想确认下载的 APK 确实是本仓库签发的，可以核对签名指纹：

```
apksigner verify --print-certs app-arm64-v8a-release.apk
```

应输出：

```
Signer #1 certificate DN: CN=YG, OU=RecipeBook, O=ztff, L=CN, ST=CN, C=CN
Signer #1 certificate SHA-256 digest: 949631304862ef19ee8e32d16c6051c412bd67500fdda169e57c6c9e3e13738d
```
