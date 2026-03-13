# Scripts: dùng env var
RABBITMQ_USER=master RABBITMQ_GROUP=master bash v2_setup_rabbitmq.sh
RABBITMQ_USER=master RABBITMQ_GROUP=master bash v2_start_rabbitmq.sh
RABBITMQ_USER=master RABBITMQ_GROUP=master bash v2_stop_rabbitmq.sh
RABBITMQ_USER=master RABBITMQ_GROUP=master bash v2_uninstall_rabbitmq.sh


# Service: sửa 4 dòng
User=root
Group=root
Environment="RABBITMQ_USER=root"
Environment="RABBITMQ_GROUP=root"