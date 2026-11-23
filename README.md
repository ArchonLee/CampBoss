# **CampBoss**

GitHub Repository

`CampBoss`

**一句话描述：**

World of Warcraft addon for automated camping, advertising, group management, and gold collection.

**功能定位：**

- Auto Tent：自动开帐篷
- Auto Advertise：自动喊话叫卖
- Auto Group：自动组队
- Auto Collect：自动收取金币

**安装：** 将 `CampBoss/` 放入国服魔兽世界「无限」客户端的 `_forever_/Interface/AddOns/`。插件标记的 Interface 版本是 `16001`。

**游戏内面板：** 输入 `/campboss`。默认 50 银、进组后 30 秒内付款、从付款起留队 180 秒。价格、时限、频道和自动确认开关从下次开摊起生效。

- **摆帐篷：** 保存帐篷物品 ID 或法术 ID，再点击「摆帐篷」。同时填写时，按钮优先使用物品。如果游戏出现选地指示圈，仍需点击地面。识别到帐篷施放成功后开摊并喊话一次；若物品法术读不到，可补填法术 ID，或摆好后手动点击「开始接单」。
- **接单与收款：** 玩家密语后尝试自动组队。可勾选「自动确认足额收款」（默认关闭）：对方已确认、报价可读且足额、我方没有放入金币或物品时，才尝试调用客户端交易确认。客户端不开放报价或阻止该操作时，仍须在原生交易窗口手动确认。
- **顾客计时：** 只管理本次开摊通过插件邀请的顾客。逾期未付款、已确认交易但实收不足，或付费留队时间已到，插件会尝试移出对应顾客。已有队友不受影响。
