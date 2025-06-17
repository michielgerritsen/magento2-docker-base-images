FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# Allow PHP version override at build time:  docker build --build-arg PHP_VERSION=7.4 .
ARG PHP_VERSION=8.2

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    # keep the daemons quiet(er)
    ES_JAVA_OPTS="-Xms512m -Xmx512m"

ENV CI=true
ENV COMPOSER_VERSION=2

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        lsb-release ca-certificates curl wget gnupg2 software-properties-common \
        supervisor openjdk-17-jdk apt-transport-https locales \
        unzip zip git jq patch ssh-client vim && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8

# PHP (Ondřej Surý PPA – gives every version 7.2-8.4)  :contentReference[oaicite:0]{index=0}
RUN add-apt-repository -y ppa:ondrej/php

# Elasticsearch APT repo and key  :contentReference[oaicite:1]{index=1}
RUN wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
        | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
        https://artifacts.elastic.co/packages/7.x/apt stable main" \
        | tee /etc/apt/sources.list.d/elastic-7.x.list

# Redis official repo & key (for 7.x)  :contentReference[oaicite:2]{index=2}
RUN curl -fsSL https://packages.redis.io/gpg | \
        gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] \
        https://packages.redis.io/deb $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/redis.list

# Supervisord
COPY templates/supervisord.conf /etc/supervisor/supervisord.conf
COPY templates/supervisord/elasticsearch.conf /etc/supervisor/conf.d/elasticsearch.conf
COPY templates/supervisord/mysql.conf /etc/supervisor/conf.d/mysql.conf
COPY templates/supervisord/php-fpm.conf /etc/supervisor/conf.d/php-fpm.conf
COPY templates/supervisord/redis.conf /etc/supervisor/conf.d/redis.conf

# ----------------------------------------------------------------
# Install the stack
# ----------------------------------------------------------------
RUN sed -i "s|__PHP_FPM_COMMAND__|/usr/sbin/php-fpm$PHP_VERSION -F|" /etc/supervisor/conf.d/php-fpm.conf && \
    mkdir -p /run/php && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        # PHP core + typical Magento extensions
        php${PHP_VERSION} \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-bz2 \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-mysqli \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-ftp \
        php${PHP_VERSION}-xsl \
        php${PHP_VERSION}-sockets \
        php${PHP_VERSION}-exif \
        # DB + cache + search
        mysql-server \
        redis-server \
        elasticsearch \
        # misc
        tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN /usr/share/elasticsearch/bin/elasticsearch-plugin install -b analysis-icu && \
    /usr/share/elasticsearch/bin/elasticsearch-plugin install -b analysis-phonetic

# Let MySQL listen on all interfaces
RUN sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Create MySQL root-password & basic secure settings (no interactive prompt)
RUN service mysql start && \
    mysql -u root -e 'CREATE DATABASE `magento`;' && \
    mysql -u root -e 'CREATE DATABASE `magento-test`;' && \
    mysql -u root -e "CREATE USER IF NOT EXISTS 'magento'@'%' IDENTIFIED WITH mysql_native_password BY 'password';" && \
    mysql -u root -e "CREATE USER IF NOT EXISTS 'magento-test'@'%' IDENTIFIED WITH mysql_native_password BY 'password';" && \
    mysql -u root -e "GRANT ALL PRIVILEGES ON * . * TO 'magento'@'%';" && \
    mysql -u root -e "GRANT ALL PRIVILEGES ON * . * TO 'magento-test'@'%';" && \
    mysql -u root -e "FLUSH PRIVILEGES;"


# Elastic needs a dedicated user
RUN getent group elasticsearch || groupadd --system elasticsearch && \
    id -u elasticsearch &>/dev/null || useradd --system -g elasticsearch elasticsearch && \
    chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

# Install Node 20
RUN curl -sL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    node --version && \
    npm --version

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
    composer --version

# Install Magerun2
# Use https://files.magerun.net/n98-magerun2-7.5.0.phar for PHP 7.4
# Use https://files.magerun.net/n98-magerun2-6.1.1.phar for PHP 7.3
# Use https://files.magerun.net/n98-magerun2-4.7.0.phar for PHP 7.2
# Use https://files.magerun.net/n98-magerun-1.103.2.phar for PHP 7.1
RUN set -e; \
    if [ "$PHP_VERSION" = "7.4" ]; then \
        url="https://files.magerun.net/n98-magerun2-7.5.0.phar"; \
    elif [ "$PHP_VERSION" = "7.3" ]; then \
        url="https://files.magerun.net/n98-magerun2-6.1.1.phar"; \
    elif [ "$PHP_VERSION" = "7.2" ]; then \
        url="https://files.magerun.net/n98-magerun2-4.7.0.phar"; \
    elif [ "$PHP_VERSION" = "7.1" ]; then \
        url="https://files.magerun.net/n98-magerun-1.103.2.phar"; \
    else \
        url="https://files.magerun.net/n98-magerun2-latest.phar"; \
    fi; \
    curl -o /usr/local/bin/n98-magerun2.phar "$url" && \
    chmod +x /usr/local/bin/n98-magerun2.phar && \
    ln -s /usr/local/bin/n98-magerun2.phar /usr/local/bin/n98-magerun2 && \
    ln -s /usr/local/bin/n98-magerun2.phar /usr/local/bin/magerun2 && \
    n98-magerun2 --version

WORKDIR /data

COPY scripts/retry retry
COPY scripts/start-services start-services
COPY scripts/stop-services stop-services
COPY templates/memory-limit-php.ini /usr/local/etc/php/conf.d/memory-limit-php.ini

EXPOSE 9000 3306 9200 6379 80
CMD ["/usr/bin/supervisord", "-n"]

RUN mkdir -p /data