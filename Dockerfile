# base image
FROM techdivision/dnmp-debian:stretch

# define labels
LABEL maintainer="j.zelger@techdivision.com"

# define composer magento repo credentials args
ARG MAGENTO_REPO_USERNAME=""
ARG MAGENTO_REPO_PASSWORD=""

# define magento install args
ARG MAGENTO_INSTALL_ADMIN_EMAIL="admin@magento.com"
ARG MAGENTO_INSTALL_ADMIN_USER="admin"
ARG MAGENTO_INSTALL_ADMIN_PASSWORD="admin123"
ARG MAGENTO_INSTALL_ADMIN_FIRSTNAME="Magento"
ARG MAGENTO_INSTALL_ADMIN_LASTNAME="Admin"
ARG MAGENTO_INSTALL_ADMIN_USE_SECURITY=1
ARG MAGENTO_INSTALL_BASE_URL="http://localhost/"
ARG MAGENTO_INSTALL_BASE_URL_SECURE="https://localhost/"
ARG MAGENTO_INSTALL_BACKEND_FRONTNAME="admin"
ARG MAGENTO_INSTALL_DB_HOST="localhost"
ARG MAGENTO_INSTALL_DB_NAME="magento"
ARG MAGENTO_INSTALL_DB_USER="magento"
ARG MAGENTO_INSTALL_DB_PASSWORD="magento"
ARG MAGENTO_INSTALL_LANGUAGE="de_DE"
ARG MAGENTO_INSTALL_CURRENCY="EUR"
ARG MAGENTO_INSTALL_TIMEZONE="Europe/Berlin"
ARG MAGENTO_INSTALL_USE_REWRITES=1
ARG MAGENTO_INSTALL_USE_SECURE=1
ARG MAGENTO_INSTALL_USE_SECURE_ADMIN=1
ARG MAGENTO_INSTALL_SAMPLEDATA=0
ARG MAGENTO_INSTALL_B2B=0
ARG MAGENTO_INSTALL_BLUEFOOT=0
ARG MAGENTO_INSTALL_EDITION="community"
ARG MAGENTO_INSTALL_VERSION="2.2.1"
ARG MAGENTO_INSTALL_STABILITY="stable"
ARG MAGENTO_INSTALL_MODE="production"
ARG MAGENTO_INSTALL_AMQP_HOST="localhost"
ARG MAGENTO_INSTALL_AMQP_PORT="5672"
ARG MAGENTO_INSTALL_AMQP_USER="guest"
ARG MAGENTO_INSTALL_AMQP_PASSWORD="guest"
ARG MAGENTO_INSTALL_AMQP_VIRTUALHOST="/"

# define ampq installation append line
ENV MAGENTO_INSTALL_AMPQ="--amqp-host=$MAGENTO_INSTALL_AMQP_HOST \
--amqp-port=$MAGENTO_INSTALL_AMQP_PORT \
--amqp-user=$MAGENTO_INSTALL_AMQP_USER \
--amqp-password=$MAGENTO_INSTALL_AMQP_PASSWORD \
--amqp-virtualhost=$MAGENTO_INSTALL_AMQP_VIRTUALHOST"

# define variables
ENV COMPOSER_AUTH="{\"http-basic\": {\"repo.magento.com\": {\"username\": \"$MAGENTO_REPO_USERNAME\", \"password\": \"$MAGENTO_REPO_PASSWORD\"}}}"
ENV COMPOSER_NO_INTERACTION=1
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV PROJECT_DIST="/var/www/dist"
ENV MAGENTO_BIN="php -d memory_limit=2048M $PROJECT_DIST/bin/magento"

# copy fs
COPY fs /tmp/fs

# start install routine
RUN \
    # disable xdebug extension
    sed -i '1s/^/;/' /etc/php/7.0/mods-available/xdebug.ini && \

    # prepare filesystem
    mkdir /var/www && \

    # install prerequisites
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
    composer global require hirak/prestissimo && \

    # create magento
    composer create-project --repository-url=https://repo.magento.com/ magento/project-$MAGENTO_INSTALL_EDITION-edition=$MAGENTO_INSTALL_VERSION --stability $MAGENTO_INSTALL_STABILITY $PROJECT_DIST && \

    # deploy fixes for various versions
    MAGENTO_VERSION_CHECK=$(php -r "echo (version_compare('2.2.0', '${MAGENTO_INSTALL_VERSION}'));") && \
    # apply sample data patches, if version is lower than 2.2.0
    if [ $? -eq 1 ]; then \
       cp -r /tmp/fs/var/www/dist/. /var/www/dist/; \
    fi && \

    # quickfix for https://github.com/techdivision/magento2-docker-imgen/issues/15 read more about
    # that topic on github under https://github.com/moby/moby/issues/34390
    find /var/lib/mysql/mysql -exec touch -c -a {} + && \

    # start and setup magento database
    mysql_start && \
    echo "GRANT ALL PRIVILEGES ON *.* TO 'magento'@'localhost' IDENTIFIED BY 'magento' WITH GRANT OPTION;"  | mysql --protocol=socket -uroot && \
    echo "CREATE DATABASE magento DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;" | mysql --protocol=socket -uroot && \

    # predefine amqp install line addon
    INSTALL_AMQP="" && \
    # enable amqp install params if edition is enterprise
    if [ "$MAGENTO_INSTALL_EDITION" = "enterprise" ]; then \
        # start rabbitmq
        /etc/init.d/rabbitmq-server start; \
        INSTALL_AMQP="$MAGENTO_INSTALL_AMPQ"; \
    fi && \

    # install magento
    $MAGENTO_BIN setup:install \
        --admin-firstname="$MAGENTO_INSTALL_ADMIN_FIRSTNAME" \
        --admin-lastname="$MAGENTO_INSTALL_ADMIN_LASTNAME" \
        --admin-email="$MAGENTO_INSTALL_ADMIN_EMAIL" \
        --admin-user="$MAGENTO_INSTALL_ADMIN_USER" \
        --admin-password="$MAGENTO_INSTALL_ADMIN_PASSWORD" \
        --admin-use-security-key="$MAGENTO_INSTALL_ADMIN_USE_SECURITY" \
        --backend-frontname="$MAGENTO_INSTALL_BACKEND_FRONTNAME" \
        --base-url="$MAGENTO_INSTALL_BASE_URL" \
        --base-url-secure="$MAGENTO_INSTALL_BASE_URL_SECURE" \
        --db-host="$MAGENTO_INSTALL_DB_HOST" \
        --db-name="$MAGENTO_INSTALL_DB_NAME" \
        --db-user="$MAGENTO_INSTALL_DB_USER" \
        --db-password="$MAGENTO_INSTALL_DB_PASSWORD" \
        --language="$MAGENTO_INSTALL_LANGUAGE" \
        --currency="$MAGENTO_INSTALL_CURRENCY" \
        --timezone="$MAGENTO_INSTALL_TIMEZONE" \
        --use-rewrites="$MAGENTO_INSTALL_USE_REWRITES" \
        --use-secure="$MAGENTO_INSTALL_USE_SECURE" \
        --use-secure-admin="$MAGENTO_INSTALL_USE_SECURE_ADMIN" \
        $INSTALL_AMQP && \

    # check if b2b extension should be installed
    if [ "$MAGENTO_INSTALL_B2B" = 1 ]; then \
        composer -d=$PROJECT_DIST require magento/extension-b2b; \
    else \
        # delete b2b relevant supervisor config files
        rm -rf /tmp/fs/etc/supervisor.d/magentoQueueConsumer_shared*; \
    fi && \

    # check if bluefoot extension should be installed, only if version is lower than 2.3.0
    MAGENTO_VERSION_CHECK=$(php -r "echo (version_compare('2.3.0', '${MAGENTO_INSTALL_VERSION}'));") && \
    if [ "$MAGENTO_INSTALL_BLUEFOOT" = 1 ] && [ $? -eq 1 ]; then \
        composer -d=$PROJECT_DIST require gene/bluefoot; \
    fi && \

    # check if sampledata should be deployed
    if [ "$MAGENTO_INSTALL_SAMPLEDATA" = 1 ]; then \
        $MAGENTO_BIN sampledata:deploy; \
    fi && \

    # magento setup upgrade
    $MAGENTO_BIN setup:upgrade && \

    # set magento install mode
    $MAGENTO_BIN deploy:mode:set $MAGENTO_INSTALL_MODE && \

    # tear down
    mysql_stop && \
    if [ "$MAGENTO_INSTALL_EDITION" = "enterprise" ]; then \
        /etc/init.d/rabbitmq-server stop; \
    fi && \

    # rollout fs
    cp -r /tmp/fs/. / && \

    # cleanup
    rm -rf /tmp/* && \
    rm -rf /etc/nginx/conf.d/default.conf

# define entrypoing
ENTRYPOINT ["/entrypoint.sh"]

# expose available ports
EXPOSE 80 81 443 3306 5671 5672 6379 9200 9300

# define default cmd
CMD ["/usr/local/bin/supervisord", "--nodaemon", "-c", "/etc/supervisord.conf"]
