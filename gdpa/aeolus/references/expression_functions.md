# Aeolus 表达式函数参考

> 来自 Aeolus `/aeolus/api/v3/misc/funcsHelp` 的离线快照（166 个函数 / 21 个分类，2026-05-12 抓取，engineType=ClickHouse / language=zh_CN / dataSetType=34）。
> 
> 当你写 Aeolus 派生字段（dim_met）的表达式时优先翻这份文档；若怀疑函数定义已经更新，再用 `gdpa-cli run aeolus --input '{"action":"list_functions","region":"sg"}'` 重新拉一次（同 region 同 engineType 在不同租户上返回一致，无需按租户重复拉取）。

## 表达式快速规则

1. 字段引用：`[字段中文名]` 或 `\`field_english_name\``，两种写法都被表达式引擎接受；保存时会被规范化为 `(\`xxx\`)` 形式（参见看板里 `fullExpr`）。
2. 字符串字面量统一用单引号：`'list_repo_merge_requests'`。
3. 布尔结果通常作为 'true' / 'false' 字符串返回，可参与 `equals(...)` / `in(...)` 比较。
4. `if(cond, then, else)` 是最常用的二选一；多分支用 `multiIf(c1, t1, c2, t2, ..., else)` 或 `case when` 模板。
5. 比较函数：`equals(a,b)` / `notEquals(a,b)` / `greater(a,b)` / `less(a,b)` 等价于 `a==b` / `a!=b`，但更适合在嵌套表达式中阅读。
6. 测试新表达式时先用 `update_field` + `dry_run=true`，再去掉 dry_run 真正写入。

## 常用表达式模板（与 UI "常用函数" 面板对齐）

| 用途 | 模板 |
|------|------|
| 分类赋值 | `CASE WHEN [字段1] = 1 THEN '分类1' WHEN [字段1] = 2 THEN '分类2' ELSE '默认值' END` |
| 条件取值 | `if(cond, then, else)` 或 `cond ? then : else` |
| 求和 | `sum([金额])` |
| 去重计数 | `uniq([用户id])` |
| 转 date | `toDate([时间戳列])` |
| 转 float64 | `toFloat64([字符串列])` |
| 转 int64 | `toInt64([字符串列])` |
| 日期对比 | `dateDiff('day', [开始日期], [结束日期])` |
| JSON 取值 | `get_json_object([json列], '$.path.to.field')` |
| URL 解析 | `parse_url([url列], 'PROTOCOL')` |
| 模糊匹配 | `like([字段], '%关键词%')` 或 `match([字段], '正则')` |

## 完整函数清单

### 聚合函数（17）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| any | `any(x)` | 选择第一个遇到的值 |  |
| argMax | `argMax(arg,val)` | 根据字段val计算其最大值. 然后取其最大值所在记录行字段arg的值 |  |
| avg | `avg(x)` | 返回表达式中所有值的平均值。只能用于数值字段 | `avg( profit ) 返回利润平均值` |
| bitmapColumnAnd | `bitmapColumnAnd(bitmap_column)` | 接收一个bimap列，该列所有bitmap做交运算 | `bitmapColumnAnd(bitmap_column) -> bitmap` |
| bitmapColumnCardinality | `bitmapColumnCardinality(bitmap_column)` | 接收一个bimap列，该列所有bitmap做并运算，返回最终结果bitmap的元素个数 | `bitmapColumnCardinality(bitmap_column) -> UInt64` |
| bitmapColumnHas | `bitmapColumnHas(bitmap_column, integer)` | 接收一个bimap列，检查该列是否包含指定元素 | `bitmapColumnHas(bitmap_column, integer) -> bool` |
| bitmapColumnOr | `bitmapColumnOr(bitmap_column)` | 接收一个bimap列，该列所有bitmap做并运算 | `bitmapColumnOr(bitmap_column) -> bitmap` |
| bitmapColumnXor | `bitmapColumnXor(bitmap_column)` | 接收一个bimap列，该列所有bitmap做异或运算 | `bitmapColumnXor(bitmap_column) -> bitmap` |
| count | `count(x)` | 计数，求行数 | `count( p_date ) 返回总天数` |
| groupArray | `groupArray(n)(date)` | 把字段的明细数据内容以数组格式折叠成一行 | `groupArray(3)(p_date) 返回：['2022-06-29', '2022-06-29', '2022-06-29']` |
| max | `max(x)` | 返回表达式中所有值的最大值。只能用于数值字段 | `max( profit ) 返回利润最大值` |
| min | `min(x)` | 返回表达式中所有值的最小值。只能用于数值字段 | `min( profit ) 返回利润最小值` |
| quantile | `quantile(level)(x)` | 返回表达式中所有值的分位数。只能用于数值字段。level范围0-1 | `quantile(0.5)(x) 返回x的0.5分位数` |
| quantileExact | `quantileExact(level)(x)` | 返回表达式中所有值的分位数。只能用于数值字段。level范围0-1。 与quantile 作用相同，是精确查询。使用quantileExact时查询耗时较长，可能因为超时而查不出数，不建议使用。 | `quantileExact(0.5)(x) 返回x的0.5分位数` |
| sum | `sum(x)` | 返回表达式中所有值的总和。只能用于数值字段 | `sum( profit ) 返回利润总和` |
| uniq | `uniq(x)` | 计数不同。 |  |
| uniqCombined | `uniqCombined(HLL_precision)(x[, ...])` | 计算不同参数值的近似数目。对于大集合(2亿或更多元素)，由于散列函数的选择不好，估计误差将大于理论值。 |  |

### 条件函数（3）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| case | `CASE  WHEN a THEN b  WHEN c THEN d ... ELSE e END` | 如果a为TRUE,则返回b；如果c为TRUE，则返回d；否则返回e |  |
| if | `if(cond, then, else), cond ? operator then : else` | 如果cond ！= 0则返回then，如果cond = 0则返回else。 cond必须是UInt8类型，then和else必须存在最低的共同类型。 | `if(1 > 2, '正确', '错误') 返回 错误` |
| multiIf | `multiIf(cond_1, then_1, cond_2, then_2...else)` | 允许您在查询中更紧凑地编写CASE运算符 参数: *cond_N — 函数返回then_N的条件。 *then_N — 执行时函数的结果。 *else — 如果没有满足任何条件，则为函数的结果。 | `multiIf(1 > 2, '正确', 2 < 0, '正确', '错误') 返回 错误` |

### LOD函数（3）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| exclude | `{exclude <维度声明> : <聚合表达式>}` | 如果表达式中指定的维度出现在视图的维度中，那么计算聚合时会排除这些维度 | `{exclude `省/自治区`:sum(`销售额`)}  或 {exclude [省/自治区]:sum([销售额])} 如果[省/自治区]出现在数据面板的维度中，那么计算聚合时会排除这个维度" 查看更多帮助：https://www.volcengine.com/docs/4726/65160` |
| fixed | `{filter=true:fixed <维度声明> : <聚合表达式>}    filter=true为非必填参数，含义为：筛选器里面的维度和指标明细筛选对fixed函数中计算聚合表达式的时候生效，true表示数据的结果受到筛选器的影响，false表示不受筛选器影响，若没有加上这个参数，默认是filter=false` | fixed详细级别表达式使用指定的维度计算值，而不引用视图中的维度。 | `{fixed `客户 id`:uniq(`订单 id`)} 或 {fixed [客户 id]:uniq([订单 id])}或 {filter=true:fixed [客户 id]:uniq([订单 id])} 每个顾客的购买次数，支持以每个客户的购买次数作为维度"` |
| include | `{include <维度声明> : <聚合表达式>}` | 除了视图中的维度之外，include 详细级别表达式还将使用表达式中指定的维度计算聚合 | `{include `客户 id`:avg(`销售额`)} 或 {include [客户 id]:avg([销售额])} 除了数据面板上的维度，还会将[客户 id]作为计算维度" 函数说明文档：https://www.volcengine.com/docs/4726/65160` |

### 表计算函数（5）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| LOOKUP | `LOOKUP( <指标> , 偏移量) along( <维度> )` | 依据维度，取当前指标位置+偏移量位置的指标值。如偏移量为-1，就是取当前指标前一位指标值。 | `LOOKUP(sum([付款金额]),-1) along([付费日期])，显示前一天的付款总额` |
| RANK_PERCENTILE | `RANK_PERCENTILE( <指标> ,'asc') along( <维度> )` | 依据维度，求指标的正序百分位（将asc替换为dsc求倒序百分位） | `RANK_PERCENTILE(sum([付款金额]),'asc') along([城市])，即由低到高计算各个城市付款金额在所在的百分位。当图表中存在其他维度（省份）时，则求各省份下，各城市付款总额在多少百分位上。` |
| RUNNING_SUM | `RUNNING_SUM( <指标> )along( <维度> )` | 依据维度滚动累加求和 | `RUNNING_SUM(sum([付款金额])) along([城市])，即依据城市滚动求和` |
| TOTAL | `TOTAL( <指标> ) along ( <维度>)` | 根据维度求指标总额。该函数通常用于计算总额百分比的场景。 | `sum([付款金额])/TOTAL(sum([付款金额])) along([城市]) ，可求得每个城市的付款总额占省份付款总额占比` |
| WINDOW_AVG | `WINDOW_AVG( <指标> ,start,end) along( <维度> )` | 窗口函数。依据维度，计算指标从start到end窗口内所有指标值均值。如start为-1，end为1，则计算指标沿着维度，从前一个到后一个窗口内，三个值的均值。 | `WINDOW_AVG(sum([付款金额]),-1,1) along([付费日期])，即依据付费日期，计算每天从前一天到后一天的付款金额均值。` |

### 字符串函数（29）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| base64Decode | `base64Decode(s)` | 解码base64编码的字符串 | `base64Decode(base64Encode('111'))` |
| base64Encode | `base64Encode(s)` | 返回字符串的base64编码 |  |
| char_length | `char_length(string)` | 假定字符串以UTF-8编码组成的文本，返回此字符串的Unicode字符长度。如果传入的字符串不是UTF-8编码，则函数可能返回一个预期外的值（不会抛出异常） |  |
| concat | `concat(s1, s2, ...)` | 将参数中的多个字符串拼接，不带分隔符 | `concat('123', 'abc', 'ABC') 返回123abcABC` |
| concat_ws | `concat_ws(String delimiter, String str1, String str2, ...)` | 返回以'delimiter'连接的字符串 | `concat_ws('_', 'abc', 'def') 返回 'abc_def'` |
| empty | `empty(x)` | 判断字符串是空为1，否则为0 | `empty('123a') 返回0` |
| endsWith | `endsWith(string,suffix)` | 返回是否以指定的后缀结尾。如果字符串以指定的后缀结束，则返回1，否则返回0。 | `endsWith('Hello, world!', 'ld!') return 1` |
| extractAll | `extractAll(haystack,pattern)` | 返回匹配到的所有子串，输出列表 | `extractAll('iioomAj12123124OOBJ123B', '\\d+') 返回 [12123124,123] 说明：从'iioomAj12123124OOBJ123B' 中查找符合'\\d+'正则模式的子串，匹配的子串 放到新数组中。'\\d+'表示匹配一个或多个数字` |
| length | `length(x)` | 返回字符串的长度 | `length('123a') 返回4` |
| lengthUTF8 | `lengthUTF8(x)` | 假定字符串以UTF-8编码组成的文本，返回此字符串的Unicode字符长度。结果类型是UInt64。 | `lengthUTF8('这是一个测试') 返回6` |
| like | `like(haystack, pattern)` | 检查字符串是否匹配正则表达式 |  |
| lower | `lower(string)` | 将字符串转为小写 |  |
| lpad,rpad | `lpad(String, len, pad_str)` | 将str进行用pad进行左补足到len位 | `lpad('abcd', 10, '.') 返回 '......abcd'` |
| match | `match(haystack,pattern)` | 字符串正则匹配，返回0或1 | `match(‘avhsca’,'vh’) 返回 1` |
| multiMatchAny | `multiMatchAny(haystack, [pattern1, pattern2, …, patternn])` | 与match相同，但如果所有正则表达式都不匹配，则返回0；如果任何模式匹配，则返回1。它使用超扫描库。对于在字符串中搜索子字符串的模式，最好使用«multisearchany»，因为它更高效。 |  |
| position | `position(haystack, needle)` | 在haystack中查找子串needle，返回子串的位置，从1开始 | `position('2121stringstrstrstrstr','str') 返回5` |
| position | `position(string, substring)` | 返回子字符串在字符串中的位置。如果没有找到子字符串，则返回0。字符串中的第一个字符为位置1. | `position('Hello', 'o') 返回5` |
| regexp_replace | `regexp_replace(String str, String str1, String str2)` | 返回将str中的str1转换为str2后的结果, 支持re2正则表达式 | `regexp_replace('world.', '^', 'hello ') 返回'hello world.'` |
| replaceAll | `replaceAll(haystack, pattern, replacement)` | 用‘replacement’子串替换‘haystack’中出现的所有‘pattern’子串 |  |
| replaceOne | `replaceOne(haystack, pattern, replacement)` | 用‘replacement’子串替换‘haystack’中第一次出的‘pattern’子串 | `replaceOne('hed1234544', '4', '*')  返回hed123*544` |
| replaceRegexpAll | `replaceRegexpAll(haystack,pattern,replacement)` | 正则匹配替换所有匹配到的pattern | `replaceRegexpAll('asd123cbbj464sd', 'sd', '-') 返回 a-123cbbj464-` |
| replaceRegexpOne | `replaceRegexpOne(haystack, pattern, replacement)` | 使用‘pattern’正则表达式替换。 |  |
| split | `split(string str, string pat)` | 按照pat字符串分割str，会返回分割后的字符串数组 | `split('abc', 'b') 返回['a', 'c']` |
| splitByChar | `splitByChar(separator, s)` | 以单个字符分割字符串 |  |
| startsWith | `startsWith(str, prefix)` | 返回是否以指定的前缀开头。如果字符串以指定的前缀开头，则返回1，否则返回0。 | `SELECT startsWith('Hello, world!', 'He'); return: 1` |
| startsWith | `startsWith(s, prefix)` | 返回是否以指定的前缀开头。如果字符串以指定的前缀开头，则返回1，否则返回0 |  |
| substring | `substring(String str, int start, int len)，substr(String str, int start, int len)` | 返回第start起长度为len的字符串 | `substring('abc', 2) 返回'bc'` |
| substringUTF8 | `substringUTF8(String str, int start, int len)` | 返回第start起长度为len的字符串，与 substring 相同，但其操作单位为Unicode字符，函数假设字符串是以UTF-8进行编码的文本 | `substringUTF8('这是一个测试',2,4)  返回：是一个测` |
| trimBoth | `trimBoth(input_string)` | 移除字符串两侧的空格 | `trimBoth('     Hello, world!     ') 返回‘Hello, world!’` |

### 日期函数（36）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| addDays | `addDays(date_time,int)` | 函数将一段时间间隔添加到Date/DateTime，然后返回Date/DateTim |  |
| date_add | `date_add (string/Date/DateTime startdate, int days)` | 返回开始日期startdate增加days天后的日期 | `date_add('2012-12-08',10) ,返回2012-12-18` |
| date_format | `date_format(Date/DateTime/String, String pattern)` | 将日期按指定格式输出 | `date_format('2019-09-09', 'yyyy') 返回 '2019'` |
| date_sub | `date_sub (string/Date/DateTime startdate, int days)` | 返回start_time 前days天的日期/时间 | `date_sub('2019-09-08', 1) 返回'2019-09-07'` |
| dateDiff | `dateDiff(Date/DateTime date1, Date/DateTime date2 [, String timezone])；
 dateDiff(String unit, Date/DateTime date1, Date/DateTime date2 [, String timezone])` | 返回两个日期的差值 | `dateDiff(now(), yesterday())返回-1` |
| day | `day(Date/DateTime/String)` | 返回dayOfMonth | `day('2019-09-12') 返回12` |
| last_day | `last_day(Date/DateTime/String date)` | 返回日期所在的月份的最后一天 | `last_day(toDateTime('2018-12-11 11:12:13'))返回 2018-12-31` |
| month | `month(Date/DateTime/String date)` | 返回日期中的月 | `month(toDateTime('2018-12-11 11:12:13'))返回 12` |
| next_day | `next_day(Date/DateTime/String date, string day_of_week)` | 返回日期中的下一个星期day_of_week | `next_day(toDate('2015-01-14'), 'TU') 返回 2015-01-20` |
| now | `now（)` | 生成当前时间日期 | `now( ) 返回 2018-12-13 10:10:12` |
| quarter | `quarter(Date/DateTime/String date)` | 返回日期所在的季度数 | `quarter(toDateTime('2018-12-11 11:12:13'))返回 4` |
| toDate | `toDate(String/UInt16 date)` | 将时间戳/字符串/自1970-01-01起的第date天转换为日期类型 | `toDate('20190909') 返回'2019-09-09'` |
| toDate larktime | `toDate((lark_time * 86400000 - 2209161600000)/1000)` | 飞书专用，返回数字对应的日期 | `toDate((lark_time * 86400000 - 2209161600000)/1000)，返回2020-05-20` |
| toDateTime | `toDateTime(x)` | 将时间戳转化为时间日期型 | `toDateTime('2020-01-01 10:20:30') 返回：2020-01-01 10:20:30` |
| today | `today( )` | 生成今天的日期 | `today( ) 返回 2018-12-13` |
| toDayOfWeek | `toDayOfWeek(date)` | 返回日期所在的星期，范围[1,7] | `todayofweek('2020-01-01') 返回3` |
| toHour | `toHour(x)` | 取时间日期的小时 | `toHour(toDateTime('2018-12-11 11:12:13'))   返回11` |
| toIntervalDay | `toIntervalDay(x)` | 日期转化为时间戳，天级别 | `toIntervalDay(toDateTime('2019-08-12 11:12:13')) 返回 1565579533` |
| toIntervalHour | `toIntervalHour(x)` | 日期转化为时间戳，小时级别 | `toIntervalHour(toDateTime('2019-08-14 11:12:13')) 返回1565579533` |
| toIntervalMinute | `toIntervalMinute(x)` | 日期转化为时间戳，分钟级别 | `toIntervalMinute(toDateTime('2019-08-14 11:12:13')) 返回1565579533` |
| toMonday | `toMonday(x)` | 将Date或DateTime向前取整到本周的星期一。 返回Date类型。 | `toMonday(toDateTime('2019-08-14 11:12:13')) 返回2019-08-12` |
| toMonth | `toMonth(string date)` | 返回日期中的月 |  |
| toRelativeWeekNum | `toRelativeWeekNum(date)` | 将Date或DateTime转换为星期数，从过去的某个固定时间点开始。 |  |
| toRelativeYearNum | `toRelativeYearNum(date_time)` | 将Date或DateTime转换为年份的编号，从过去的某个固定时间点开始 |  |
| toStartOfDay | `toStartOfDay(string datetime)` | 将DateTime向前取整到当日的开始。 |  |
| toStartOfFifteenMinutes | `toStartOfFifteenMinutes（x)` | 截取时间日期到最近的15的倍数分钟（之后归零），返回日期 | `toStartOfFiveMinute(toDateTime('2018-12-11 11:12:13')) 返回 2018-12-11 11:00:00` |
| toStartOfFiveMinute | `toStartOfFiveMinute（x）` | 截取时间日期到最近的5的倍数分钟（之后归零），返回日期 | `toStartOfFiveMinute(toDateTime('2018-12-11 11:12:13')) 返回 2018-12-11 11:10:00` |
| toStartOfHour | `toStartOfHour(x)` | 将DateTime向前取整到当前小时的开始。 | `toStartOfHour(toDateTime('2018-12-11 11:12:13')) 返回11` |
| toStartOfInterval | `toStartOfInterval(time_or_data, INTERVAL x unit [, time_zone])` | 这是名为toStartOf*的所有函数的通用函数。例如， toStartOfInterval（t，INTERVAL 1 year）返回与toStartOfYear（t）相同的结果， toStartOfInterval（t，INTERVAL 1 month）返回与toStartOfMonth（t）相同的结果， toStartOfInterval（t，INTERVAL 1 day）返回与toStartOfDay（t）相同的结果， toStartOfInterval（t，INTERVAL 15 minute）返回与toStartOfFifteenMinutes（t）相同的结果。 | `toStartOfInterval(toDateTime('2019-10-10 09:09:20'),INTERVAL 1 year) 返回 2019-01-01` |
| toStartOfMinute | `toStartOfMinute( )` | 截取时间日期到分钟（之后归零），返回日期 | `toStartOfMinute(toDateTime('2018-12-11 11:12:13')) 返回 2018-12-11 11:12:00` |
| toStartOfTenMinutes | `toStartOfTenMinutes(x)` | 将DateTime以十分钟为单位向前取整到最接近的时间点 | `toStartOfTenMinute(toDateTime('2018-12-11 11:12:13')) 返回 2018-12-11 11:12:00` |
| toUnixTimestamp | `toUnixTimestamp( )` | 将DateTime转换为unix时间戳 |  |
| toWeek | `toWeek(date[,mode])` | 返回日期所在的周, 范围[0, 53] | `toWeek(toDate('2019-12-06'), 3) 返回 49` |
| toYear | `toYear(string date)` | 返回日期中的年 |  |
| unix_timestamp | `unix_timestamp(Date/DateTime/String)` | 将日期转换为对应的时间戳timestamp | `unix_timestamp(toDateTime('2019-09-09 09:00:00'), 'time: %F %T') 返回'1567990800'` |
| year | `year(Date/DateTime/String date)` | 返回日期中的年 | `year(toDateTime('2018-12-11 11:12:13'))返回 2018` |

### 数学函数（13）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| cbrt | `cbrt(x)` | 返回参数的立方根 |  |
| cos | `cos(x)` | 返回x的三角余弦值 |  |
| equals | `equals(a, b)` | 判断两数是否相等，相等返回1，否则返回0. | `equals('hello','hello') 返回1` |
| exp | `exp(x)` | 接收一个数值类型的参数并返回它的指数 |  |
| greater | `greater(a, b)` | 判断数a是否大于数b，a大于b返回1，否则返回0 | `greater(12, 10) 返回1` |
| less | `less(a, b)` | 判断数a是否小于数b，a小于b返回1，否则返回0 | `less(12,23) 返回1` |
| log,ln | `log(x),ln(x)` | 接收一个数值类型的参数并返回它的对数 |  |
| negate | `negate(x)` | 返回接收参数的相反数 |  |
| pow | `pow(x, y)` | 接受x和y两个参数。返回x的y次方。 | `pow(2, 3) 返回 8` |
| power | `power(x, y)` | 接受x和y两个参数。返回x的y次方 |  |
| sin | `sin(x)` | 返回x的三角正弦值 |  |
| sqrt | `sqrt(x)` | 接受一个非负数值类型的参数并返回它的算术平方根。 | `sqrt(4) 返回2` |
| tan | `tan(x)` | 返回x的三角正切值 |  |

### 算术函数（3）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| abs | `abs(a)` | 计算数字（a）的绝对值 |  |
| ceil, ceiling | `ceil(x[, N]), ceiling(x[, N])` | 返回大于或等于x的最小舍入数。N表示舍入的精确程度。 | `ceil(12.34343,3) 返回12.344` |
| floor | `floor(x[, N])` | 返回小于或等于x的最大舍入数。N表示舍入的精确程度。 | `floor(123.45, 1) 返回123.4` |

### 取整函数（1）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| round | `round(x,[N])` | 将值取整到指定的小数位数。 该函数按顺序返回最近的数字。如果给定数字包含多个最近数字，则函数返回其中最接近偶数的数字（银行的取整方式）。 | `round(123.883, 1) 返回 123.9` |

### 取模函数（1）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| pmod | `pmod(Int a, Int b)` | 浮点数会转换为整数取模, 如有特殊需求, 可在后期支持 | `pmod(10, 3) 返回 1` |

### 随机函数（1）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| rand | `rand( )` | 返回一个UInt32类型的随机数字，所有UInt32类型的数字被生成的概率均相等 |  |

### 类型转换函数（20）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| cast | `cast(X, 'Y')` | 通用强转函数，将名称为X的任意类型数据，转化成Y格式 | `将 int 类型的 uid 转换为 String 类型  CAST (uid, 'String')` |
| parseDateTimeBestEffort | `parseDateTimeBestEffort()` | 将数字类型参数解析为Date或DateTime类型。 与toDate和toDateTime不同，parseDateTimeBestEffort可以进行更复杂的日期格式。 |  |
| parseDateTimeBestEffortOrNull | `parseDateTimeBestEffortOrNull()` | 将数字类型参数解析为Date或DateTime类型,遇到无法处理的日期格式时返回null |  |
| parseDateTimeBestEffortOrZero | `parseDateTimeBestEffortOrZero()` | 将数字类型参数解析为Date或DateTime类型,遇到无法处理的日期格式时返回零Date或零DateTime |  |
| toDateOrNull | `toDateOrNull(a)` | 将a的数据类型转成date  or null |  |
| toDateOrZero | `toDateOrZero(x)` | 将数据类型转化为DATE格式，否则返回0 | `toDateOrZero(toDateTime('2018-12-11 11:12:13')) 返回2018-12-11` |
| toDateTimeOrNull | `toDateTimeOrNull(a)` | 将a的数据类型转成datetime or null |  |
| toFloat32OrZero | `toFloat32OrZero( )` | 将数值字符串型转化为数值型，失败返回0 | `toFloat32OrZero(‘-123’)  返回-123` |
| toFloat64 | `toFloat64(a)` | 将a的数据类型转成float64 |  |
| toFloat64OrZero | `toFloat64OrZero(a)` | 将a的数据类型转成float或0 |  |
| toInt32 | `toInt32(a)` | 将a的数据类型转成int32 |  |
| toInt64 | `toInt64(x)` | 将数据类型转化为int格式(64个字节) | `toInt64(123.883) 返回 123` |
| toIntervalMonth | `toIntervalMonth( )` | 将数字类型参数转换为Interval类型（时间区间） |  |
| toString | `toString(x)` | 将数值型、字符型、日期等转化为字符型 | `toString('2018-12-24') 返回2018-12-24` |
| toUInt16OrZero | `toUInt16OrZero(x)` | 将无符号整数字符型转化为整数型，否则返回0 | `toUInt8OrZero('123') 返回123` |
| toUInt32 | `toUInt32(a)` | 将a的数据类型转成Uint32 |  |
| toUInt32OrZero | `toUInt32OrZero(x)` | 将数据类型转化为int格式(32个字节)，失败则为0 |  |
| toUInt64OrZero | `toUInt64OrZero(x)` | 将数据类型转化为int格式(64个字节)，失败则为0 | `toUInt64OrZero('123') 返回123` |
| toUInt8 | `toUInt8(a)` | 将a的数据类型转成Uint8 |  |
| toUInt8OrZero | `toUInt8OrZero(x)` | 将无符号整数字符型转化为整数型，否则返回0 | `toUInt8OrZero('123.12') 返回0` |

### Nullable处理函数（5）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| assumeNotNull | `assumeNotNull( )` | 将Nullable类型的值转换为非Nullable类型的值 |  |
| coalesce | `coalesce(x,...)` | 检查从左到右是否传递了“NULL”参数并返回第一个非'NULL参数。 | `coalesce(null,null,a,b,null) 返回 a` |
| isNan | `isNan(x)` | 检查参数是否为Nan,是nan返回1,不是返回0 | `isNan(nan) 返回1` |
| isNotNull | `isNotNull(x)` | 检查参数是否不为 NULL. 是返回1，否返回0 | `isNotNull('abc') 返回1` |
| isNull | `isNull(x)` | 检查参数是否为NULL,是null返回1,不是返回0 | `isNull(null) 返回1` |

### JSON函数（6）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| get_json_object | `get_json_object(string json_string, string path)` | 返回JSON中path指定的元素 | `get_json_object('{"n_s" : [{"ac":"abc","xz":"xz"}, {"def":"def"}], "n_i" : [1, 23]}', '$.n_s[0].ac'); 返回'abc'` |
| visitParamExtractBool | `visitParamExtractBool(params, name)` | 解析一个 true/false 值. 结果是 UInt8 |  |
| visitParamExtractFloat | `visitParamExtractFloat(params, name)` | 将名为“name”的字段的值解析成float64 |  |
| visitParamExtractRaw | `visitParamExtractRaw(params, name)` | 返回字段的值，包含空格符。 | `visitParamExtractRaw('{"abc":{"def":[1,2,3]}}', 'abc') = '{"def":[1,2,3]}'` |
| visitParamExtractUInt | `visitParamExtractUInt(params, name)` | 将名为“name”的字段的值解析成UInt64。如果这是一个字符串字段，函数将尝试从字符串的开头解析一个数字。如果该字段不存在，或无法从它中解析到数字，则返回0。 |  |
| visitParamHas | `visitParamHas(params, name)` | 检查是否存在“name”名称的字段 |  |

### URL函数（3）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| cutToFirstSignificantSubdomain | `cutToFirstSignificantSubdomain( )` | 返回包含顶级域名与第一个有效子域名之间的内容 | `cutToFirstSignificantSubdomain('https://news.yandex.com.tr/') = 'yandex.com.tr'` |
| domain | `domain(x)` | 返回URL的域名 | `domain('http://www.google.com') 返回 www.google.com` |
| parse_url | `parse_url(String url, String name)` | 返回url中为name的部分, 无法解析返回空字符串 | `parse_url('https://www.google.com', 'PROTOCOL') 返回https` |

### 数组函数（5）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| arrayConcat | `arrayConcat(array)` | 合并参数中传递的所有数组。 | `SELECT arrayConcat([1, 2], [3, 4], [5, 6]) AS res ┌─res─────┐ │ [1,2,3,4,5,6] │ └───────┘` |
| arrayJoin | `arrayJoin(array)` | 将一个数组中的元素展开成多行 | `arrayJoin([1,2,3]) 返回： 1 2 3` |
| has | `has(arr,elem)` | 检查数组是否具有elem元素。 如果元素不在数组中，则返回0;如果在，则返回1。 | `has([1,2,3],2)` |
| indexOf | `indexOf(arr, x)` | 返回元素x在数组中第一次出现的索引，如果元素x不存在数组中返回0 | `indexOf([1, 2, 4], 4)` |
| notEmpty | `notEmpty()` | 对于空字符串返回0，对于非空字符串返回1 |  |

### map函数（2）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| map{'key'} | `[map型字段名]{'[待提取字段名]'}` | 从map类型的字段中提取某一字段数据 | `select deductions{'Federal Taxes'} from employees limit 1;` |
| str_to_map | `map(String value, String kv_delimiter, String item_delimiter)` | String转map类型 | `str_to_map('a:b,c:d', ',', ':') 返回 {'a': 'b', 'c': 'd'}` |

### 位操作函数（2）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| bitAnd | `bitAnd(a, b)` | 结果类型是一个整数，其位数等于其参数的最大位。如果至少有一个参数为有符数字，则结果为有符数字。如果参数是浮点数，则将其强制转换为Int64 |  |
| bitOr | `bitOr(a, b)` | 返回两数按位或操作的结果 |  |

### 进制转换函数（2）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| bin | `bin(Int/DateTime/String)` | 转换为二进制数 | `bin(10) 返回'1010'` |
| conv | `conv(String/Int num, Int from_base, Int to_base)` | 进制转换 | `conv('10',10,2) 返回'1010'` |

### Hash函数（2）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| cityHash64 | `cityHash64()` | 计算任意数量字符串的CityHash64或使用特定实现的Hash函数计算任意数量其他类型的Hash |  |
| intHash64 | `intHash64( )` | 从任何类型的整数计算64位哈希码 |  |

### 其他函数（7）

| 函数 | 签名 | 说明 | 示例 |
|------|------|------|------|
| generateUUIDv4 | `generateUUIDv4([x])` | 生成uuid |  |
| hostName | `hostName()` | 返回一个字符串，其中包含执行此函数的主机的名称。 |  |
| isInfinite | `isInfinite(x)` | 判断参数是否为无穷 |  |
| SHA1, SHA224, SHA256 | `SHA1(s), SHA224(s), SHA256(s)` | 根据SHA-1, SHA-224, SHA-256算法计算字符串的hash值 | `hex(SHA1('abc')) 返回A9993E364706816ABA3E25717850C26C9CD0D89D` |
| size | `size(Array/Map/String)` | 返回里面的元素个数 | `size(map('a', 'b', 'c', 'd')) 返回2` |
| toRegion | `toRegion(string code, int code_type)` | 根据输入的国家代码/区域代码，统一映射并返回包含 region_code、ops_team、second_area_code、first_area_code、business_region_code、business_ops_team、second_business_area_code、first_business_area_code 共 8 个维度区域信息的数组。 | `toRegion('AC', 1)[1] 获取国家代码为 AC 的所映射的region_code` |
| toUUID | `toUUID(String)` | 将string转化为uuid | `toUUID('61f0c404-5cb3-11e7-907b-a6006ad3dba0')` |

_共 166 个函数_
