ARG PHP_VERSION=php74-fpm
FROM srcoder/development-php:${PHP_VERSION}

ENV CI=true

RUN apt update --fix-missing && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt install -y gnupg procps apt-transport-https lsb-release software-properties-common jq && \
    curl -L https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - && \
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-7.x.list && \
    wget https://repo.mysql.com//mysql-apt-config_0.8.18-1_all.deb && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 467B942D3A79BD29 && \
    dpkg -i mysql-apt-config_0.8.18-1_all.deb && \
    apt update && \
    echo "[mysqld]\ndefault-authentication-plugin=mysql_native_password" > ~/.my.cnf && \
    apt install -y elasticsearch mysql-server mysql-client && \
    echo "Replacing Elasticsearch config values" && \
    sed -i 's/^elasticsearch hard memlock.*/elasticsearch hard memlock 100000/' /etc/security/limits.conf && \
    sed -i 's/^ES_HEAP_SIZE=.*/ES_HEAP_SIZE=128m/' /etc/default/elasticsearch && \
    sed -i 's/^MAX_LOCKED_MEMORY=.*/MAX_LOCKED_MEMORY=100000/' /etc/default/elasticsearch && \
    sed -i 's/^#ES_JAVA_OPTS=.*/ES_JAVA_OPTS=-server/' /etc/default/elasticsearch && \
    sed -i 's/^index.number_of_shards:.*/index.number_of_shards: 1/; s/^index.number_of_replicas:.*/index.number_of_replicas: 0/' /etc/elasticsearch/elasticsearch.yml && \
    /usr/share/elasticsearch/bin/elasticsearch-plugin install -b analysis-icu && \
    /usr/share/elasticsearch/bin/elasticsearch-plugin install -b analysis-phonetic && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i "s/.*bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf && \
    echo 'memory_limit = 4G' >> /usr/local/etc/php/conf.d/memory-limit-php.ini && \
    echo 'max_execution_time = 300' >> /usr/local/etc/php/conf.d/memory-limit-php.ini && \
    rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
    composer self-update && \
    service elasticsearch start && \
    /bin/bash -c "/usr/bin/mysqld_safe &" && \
    sleep 5 && \
    mysql -u root -e 'CREATE DATABASE `magento`;' && \
    mysql -u root -e 'CREATE DATABASE `magento-test`;' && \
    mysql -u root -e "CREATE USER 'magento'@'%' IDENTIFIED BY 'password';" && \
    mysql -u root -e "CREATE USER 'magento-test'@'%' IDENTIFIED BY 'password';" && \
    mysql -u root -e "GRANT ALL PRIVILEGES ON * . * TO 'magento'@'%';" && \
    mysql -u root -e "GRANT ALL PRIVILEGES ON * . * TO 'magento-test'@'%';" && \

COPY scripts/retry retry