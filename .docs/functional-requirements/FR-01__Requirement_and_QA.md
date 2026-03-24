## Requirement
Module 1: IOC OpenCTI mới -> Confirmed -> Lưu vào ES trên TI server (UNIQUE) -> Tool (GO) -> IDS Blacklist TI Server + update version
    + Check virut-total

+ Viết 1 program bằng go đọc dữ liệu IOC theo ngày mới đã được comfirmed trong ES và insert dữ liệu vào mysql + update version 
    + Hiểu được scheme của index IOC của OpenCTI
    + Hiểu được scheme của bảng mysql (viết cậu lệnh upsert dữ liệu mới theo ngày)
+ python query IOC, id/domain, hashlist cái mới trong es cho để viết vào bảng của mysql
Virut total: giả trình duyệt - no key.

```sh
ssh root@163.223.58.154
Vipstmt@828912

mysql -u root -p ids
vipstmt@828912

# table
ids_blacklist
hashlist
```






