FROM alpine:latest

# Initial updates
RUN apk update && \
    apk upgrade && \
    rm -rf /var/cache/apk/* /var/log/*

# Install packages
RUN apk add --no-cache \
    autoconf \
    automake \
    bash \
    busybox-suid \
    openssh-keygen \
    mandoc \
    # Init related
    tini \
    openrc \
    busybox-initscripts \
    # Apache
    apache2 \
    apache2-proxy \
    # PHP-FPM (FastCGI Process Manager) is an alternative PHP FastCGI implementation with some additional features useful for sites of any size, especially busier sites - https://php-fpm.org
    php7-fpm \
    php7 \
    php7-apcu \
    php7-curl \
    php7-ctype \
    php7-dom \
    php7-common \
    php7-gd \
    php7-iconv \
    php7-json \
    php7-mbstring \
    php7-pecl-memcached \
    php7-openssl \
    php7-opcache \
    php7-pdo \
    php7-phar \
    php7-session \
    php7-simplexml \
    php7-soap \
    php7-tokenizer \
    php7-xdebug \
    php7-xml \
    php7-xmlwriter \
    php7-pecl-yaml \
    php7-zip \
    composer \
    grep \
    git \
    curl \
    vim \
    shadow

# Change shell to bash
RUN usermod -s /bin/bash root && bash --login
# Bash config updates for root user
RUN cd && bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"

# Configure to use php fpm and don't use /var/www to store everything (modules and logs)
RUN \
    # Disable mpm_prefork
    sed -i 's/LoadModule mpm_prefork_module/#LoadModule mpm_prefork_module/g' /etc/apache2/httpd.conf && \
    # Enable mpm_event
    sed -i 's/#LoadModule mpm_event_module/LoadModule mpm_event_module/g' /etc/apache2/httpd.conf && \
    # Enable rewrite mod
    sed -i 's/#LoadModule rewrite_module/LoadModule rewrite_module/g' /etc/apache2/httpd.conf && \
    # Remove useless module bundled with proxy
    sed -i 's/LoadModule lbmethod/#LoadModule lbmethod/g' /etc/apache2/conf.d/proxy.conf && \
    # Enable deflate mod
    sed -i 's/#LoadModule deflate_module/LoadModule deflate_module/g' /etc/apache2/httpd.conf && \
    # Enable expires mod
    sed -i 's/#LoadModule expires_module/LoadModule expires_module/g' /etc/apache2/httpd.conf && \
    # Enable session mod
    sed -i 's/#LoadModule session_module/LoadModule session_module/g' /etc/apache2/httpd.conf && \
    # Do not expose PHP version to the world
    sed -i 's/expose_php = On/expose_php = Off/g' /etc/php7/php.ini && \
    # Disable APC - it has been replaced by APCu and opcache in PHP7 - https://pecl.php.net/package/apc
    echo 'apc.enabled = Off' >> /etc/php7/php.ini && \
    # Increase memory_limit
    sed -i 's/memory_limit.*/memory_limit = 2G/g' /etc/php7/php.ini && \
    # max_execution_time to 5min
    sed -i 's/max_execution_time.*/max_execution_time = 300/g' /etc/php7/php.ini && \
    # max_input_time to 2min
    sed -i 's/max_input_time.*/max_input_time = 120/g' /etc/php7/php.ini && \
    # Change DocumentRoot to /var/www
    sed -i 's/var\/www\/localhost\/htdocs/var\/www\/html/g' /etc/apache2/httpd.conf && \
    # Change ServerRoot to /usr/local/apache
    sed -i 's/ServerRoot \/var\/www/ServerRoot \/usr\/local\/apache/g' /etc/apache2/httpd.conf && \
    # Make sure PHP-FPM executes as apache user
    sed -i 's/user = nobody/user = apache/g' /etc/php7/php-fpm.d/www.conf && \
    sed -i 's/group = nobody/group = apache/g' /etc/php7/php-fpm.d/www.conf && \
    # Shortcut cli commands
    echo 'alias l="ls -la"; alias s="cd .."' >> ~/.profile && \
    # Prepare Apache log dir
    mkdir -p /var/log/apache2 && \
    # Clean base directory
    rm -rf /var/www/* && \
    # Apache configs in one place
    mkdir -p /run/apache2 /usr/local/apache && \
    ln -s /usr/lib/apache2 /usr/local/apache/modules && \
    ln -s /var/log/apache2 /usr/local/apache/logs

# Make sure apache can read&right to docroot
RUN chown -R apache:apache /var/www
# Make sure apache can read&right to logs
RUN chown -R apache:apache /var/log/apache2
# Allow Apache to create pid
RUN chown -R apache:apache /run/apache2

# Change shell for apache user so that it can login
RUN usermod -s /bin/bash apache

# Some shell aliases
RUN echo "alias l='ls -la' \
    alias s='cd ..' \
    alias grep='grep --color=auto'" > /var/www/.bashrc

### Continue execution as Apache user ###
USER apache

# Change to bash
RUN bash --login
# Bash config updates for apache user
RUN cd && bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"

# Define Grav specific version of Grav or use latest stable
ENV GRAV_VERSION latest

# Install grav
WORKDIR /var/www
RUN curl -o grav-admin.zip -SLk https://getgrav.org/download/core/grav-admin/${GRAV_VERSION} && \
    unzip grav-admin.zip && \
    mv -f /var/www/grav-admin /var/www/html && \
    rm grav-admin.zip

# Update Grav plugins
RUN cd /var/www/html && bin/gpm -y update

# Create cron job for Grav maintenance scripts
RUN (crontab -l; echo "* * * * * cd /var/www/html; /usr/bin/php bin/grav scheduler 1 >> /dev/null 2>&1") | crontab -
# Cron requires that each entry in a crontab end in a newline character. If the last entry in a crontab is missing the newline, cron will consider the crontab (at least partially) broken and refuse to install it.
RUN (crontab -l; echo "") | crontab -

# Generate RSA keys to be able to use 'git clone' with a public key
RUN echo -e 'y' | /usr/bin/ssh-keygen -t rsa -b 4096 -q -N "" -f ~/.ssh/id_rsa
# Make sure no one but the owner can read the private key
RUN chmod 600 ~/.ssh/id_rsa

# Accept incoming HTTP requests
EXPOSE 80

### Return to root user ###
USER root

# syslog option '-Z' was changed to '-t', change this in /etc/conf.d/syslog so that syslog (and then cron) actually starts
# https://gitlab.alpinelinux.org/alpine/aports/-/issues/9279
RUN sed -i 's/SYSLOGD_OPTS="-Z"/SYSLOGD_OPTS="-t"/g' /etc/conf.d/syslog

# Provide container inside image for data persistence
VOLUME ["/var/www"]

# vhost config
COPY vhost.conf /etc/apache2/conf.d/vhost.conf

# Start PHP-FPM and Apache
CMD crond && php-fpm7 -D && httpd
