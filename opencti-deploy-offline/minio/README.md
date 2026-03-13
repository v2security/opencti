# Scripts: dùng env var
MINIO_USER=master MINIO_GROUP=master bash v2_setup_minio.sh
MINIO_USER=master MINIO_GROUP=master bash v2_start_minio.sh
MINIO_USER=master MINIO_GROUP=master bash v2_stop_minio.sh
MINIO_USER=master MINIO_GROUP=master bash v2_uninstall_minio.sh


# Service: sửa 4 dòng
User=root
Group=root
Environment="MINIO_USER=root"
Environment="MINIO_GROUP=root"