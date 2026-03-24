
## Table ids_blacklist;
> Bảng này là blacklist IOC / threat intelligence.

```sh
mysql> SELECT * FROM ids_blacklist LIMIT 5;
+----------+-------+-----------------+-----------+---------+---------+--------+----------------+
| id       | stype | value           | country   | source  | srctype | type   | version        |
+----------+-------+-----------------+-----------+---------+---------+--------+----------------+
|        2 | ip    | 59.153.249.220  | none      | malware |         | local  | 10191005000000 |
| 10000001 | ip    | 103.14.120.121  | India     | malware | v2      | global | 20250505153828 |
| 10000002 | ip    | 103.19.89.55    | India     | malware | v2      | global | 20191005003131 |
| 10000003 | ip    | 103.224.212.222 | Australia | malware | v2      | global | 20250518120606 |
| 10000004 | ip    | 103.24.13.91    | Indonesia | malware | v2      | global | 20191005003131 |
+----------+-------+-----------------+-----------+---------+---------+--------+----------------+
5 rows in set (0.00 sec)

## Schemas 
mysql> DESCRIBE ids_blacklist;
+---------+----------+------+-----+---------+-------+
| Field   | Type     | Null | Key | Default | Extra |
+---------+----------+------+-----+---------+-------+
| id      | int      | NO   | PRI | NULL    |       |
| stype   | tinytext | NO   |     | NULL    |       |
| value   | text     | NO   |     | NULL    |       |
| country | tinytext | NO   |     | NULL    |       |
| source  | tinytext | NO   |     | NULL    |       |
| srctype | tinytext | NO   |     | NULL    |       |
| type    | tinytext | NO   |     | NULL    |       |
| version | tinytext | NO   |     | NULL    |       |
+---------+----------+------+-----+---------+-------+
8 rows in set (0.00 sec)

mysql> SELECT DISTINCT stype FROM ids_blacklist;
+--------+
| stype  |
+--------+
| ip     |
| domain |
+--------+
2 rows in set (0.16 sec)

mysql> SELECT COUNT(*) FROM ids_blacklist;
+----------+
| COUNT(*) |
+----------+
|    67916 |
+----------+
1 row in set (0.01 sec)

### Index 
mysql> SHOW INDEX FROM ids_blacklist;
+---------------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
| Table         | Non_unique | Key_name | Seq_in_index | Column_name | Collation | Cardinality | Sub_part | Packed | Null | Index_type | Comment | Index_comment | Visible | Expression |
+---------------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
| ids_blacklist |          0 | PRIMARY  |            1 | id          | A         |       67627 |     NULL |   NULL |      | BTREE      |         |               | YES     | NULL       |
+---------------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
1 row in set (0.00 sec)
```

## Table hashlist;
```sh
mysql> SELECT * FROM hashlist LIMIT 5;
+---------+----------------------+-----------------------------+----------------------------------+--------+----------------+
| id      | description          | name                        | value                            | type   | version        |
+---------+----------------------+-----------------------------+----------------------------------+--------+----------------+
| 1000001 | Kaspersky            | Trojan.MSIL.HydraPOS.alf    | 1daec173bef2d6c442c4a59db74be63d | global | 30240912070005 |
| 1000002 | FireEye              | Trojan.Linux.Generic.162681 | a71ad3167f9402d8c5388910862b16ae | global | 30240912070005 |
| 1000003 | Sophos               | Linux/Miner-XE              | 6bffa50350be7234071814181277ae79 | global | 30240912070005 |
| 1000004 | FireEye              | Trojan.Linux.Generic.159209 | 6d5b0d4b5b459ff3f68a58f3bfad3707 | global | 30240912070005 |
| 1000005 | TrendMicro-HouseCall | TROJ_GEN.R03BH0CLO19        | 00698e21d49fb92f086cc342915ecad6 | global | 30240912070005 |
+---------+----------------------+-----------------------------+----------------------------------+--------+----------------+
5 rows in set (0.00 sec)

mysql> DESCRIBE hashlist;
+-------------+----------+------+-----+---------+----------------+
| Field       | Type     | Null | Key | Default | Extra          |
+-------------+----------+------+-----+---------+----------------+
| id          | int      | NO   | PRI | NULL    | auto_increment |
| description | tinytext | NO   |     | NULL    |                |
| name        | tinytext | NO   |     | NULL    |                |
| value       | tinytext | NO   |     | NULL    |                |
| type        | tinytext | NO   |     | NULL    |                |
| version     | tinytext | NO   |     | NULL    |                |
+-------------+----------+------+-----+---------+----------------+
6 rows in set (0.00 sec)

mysql> SELECT DISTINCT type FROM hashlist;
+--------+
| type   |
+--------+
| global |
+--------+
1 row in set (0.80 sec)

mysql> SELECT COUNT(*) FROM hashlist;
+----------+
| COUNT(*) |
+----------+
|   336884 |
+----------+
1 row in set (0.16 sec)

mysql> SHOW INDEX FROM hashlist;
+----------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
| Table    | Non_unique | Key_name | Seq_in_index | Column_name | Collation | Cardinality | Sub_part | Packed | Null | Index_type | Comment | Index_comment | Visible | Expression |
+----------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
| hashlist |          0 | PRIMARY  |            1 | id          | A         |      337388 |     NULL |   NULL |      | BTREE      |         |               | YES     | NULL       |
+----------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
1 row in set (0.00 sec)
```

