# vim: sw=2 et

ARG REQUIRED_TOOLS_IN_DIST_IMAGE="\
  /bin/basename \
  /bin/cat \
  /bin/cp \
  /bin/cut \
  /bin/dirname \
  /bin/echo \
  /bin/env \
  /bin/false \
  /bin/find \
  /bin/ls \
  /bin/mkdir \
  /bin/printf \
  /bin/rm \
  /bin/sh \
  /bin/sort \
  /bin/stat \
  /bin/true \
  /usr/bin/chmod \
  /usr/bin/chown \
  /usr/bin/envsubst \
  /usr/bin/id \
  /usr/sbin/nologin \
  "

FROM fedora:37 AS base-os
RUN dnf upgrade --refresh -y \
  && dnf install -y \
    curl \
    gcc \
    gettext-envsubst \
    git \
    lld \
    openssl-devel \
    tree \
    tzdata \
    upx \
    wget

FROM base-os AS build

ARG BUILD_THROTTLE
ARG HEADERS_MORE_VERSION
ARG NGINX_COMMIT
ARG NGINX_VERSION
ARG NGX_BROTLI_COMMIT
ARG NJS_COMMIT
ARG NJS_VERSION
ARG REQUIRED_TOOLS_IN_DIST_IMAGE

RUN \
  env | sort

WORKDIR /usr/src/

RUN \
  echo "Downloading nginx $NGINX_VERSION (rev $NGINX_COMMIT from 'default' branch) ..." \
  && cd /usr/src \
  && wget --no-verbose https://hg.nginx.org/nginx/archive/${NGINX_COMMIT}.tar.gz -O nginx-${NGINX_COMMIT}.tar.gz \
  && tar -xf nginx-${NGINX_COMMIT}.tar.gz

RUN \
  echo "Downloading nginx njs module v${NJS_VERSION} (rev $NJS_COMMIT) ..." \
  && cd /usr/src \
  && wget --no-verbose https://hg.nginx.org/njs/archive/${NJS_COMMIT}.tar.gz -O njs-${NJS_COMMIT}.tar.gz \
  && tar -xf njs-${NJS_COMMIT}.tar.gz

RUN \
  echo "Cloning brotli module (rev $NGX_BROTLI_COMMIT) ..." \
  && mkdir -pv /usr/src/ngx_brotli-$NGX_BROTLI_COMMIT \
  && cd /usr/src/ngx_brotli-$NGX_BROTLI_COMMIT \
  && git init \
  && git remote add origin https://github.com/google/ngx_brotli.git \
  && git fetch --depth 1 origin $NGX_BROTLI_COMMIT \
  && git checkout --recurse-submodules -q FETCH_HEAD \
  && git submodule update --init --depth 1

RUN \
  echo "Downloading headers-more module (rev $HEADERS_MORE_VERSION) ..." \
  && cd /usr/src \
  && wget --no-verbose https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${HEADERS_MORE_VERSION}.tar.gz -O headers-more-nginx-module-${HEADERS_MORE_VERSION}.tar.gz \
  && tar -xf headers-more-nginx-module-${HEADERS_MORE_VERSION}.tar.gz

# tools required for source patching and building
RUN \
  dnf install -y \
    GeoIP-devel \
    autoconf \
    automake \
    clang \
    cmake \
    diffutils \
    gd-devel \
    glib2-devel \
    glibc-devel \
    glibc-headers-x86 \
    kernel-headers \
    libpng-devel \
    libtiff-devel \
    libtool \
    libxcrypt-devel \
    libxml2-devel \
    libxslt-devel \
    make \
    pax-utils \
    pcre2-devel \
    perl-FindBin \
    perl-IPC-Cmd \
    perl-Pod-Html \
    perl-devel \
    python3 \
    python3-pip \
    readline-devel \
    redhat-rpm-config \
    which \
    zlib-devel

  # --with-http_perl_module \
  # --with-http_image_filter_module \
  # --with-http_xslt_module \
  # --with-mail \
  # --with-mail_ssl_module \
  # --with-compat \ # enables dynamic modules compatibility
  # --with-http_random_index_module \
  # --with-http_slice_module \
  # --with-http_secure_link_module \
  # --with-http_dav_module
ARG CONFIG="\
  --add-module=/usr/src/headers-more-nginx-module-$HEADERS_MORE_VERSION \
  --add-module=/usr/src/ngx_brotli-$NGX_BROTLI_COMMIT \
  --add-module=/usr/src/njs-$NJS_COMMIT/nginx \
  --build=$NGINX_COMMIT \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --group=nginx \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-log-path=/var/log/nginx/access.log \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --lock-path=/var/run/nginx/nginx.lock \
  --modules-path=/usr/lib/nginx/modules \
  --pid-path=/var/run/nginx/nginx.pid \
  --prefix=/etc/nginx \
  --sbin-path=/usr/bin/nginx \
  --user=nginx \
  --with-debug \
  --with-file-aio \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_realip_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_v2_module \
  --with-pcre-jit \
  --with-stream \
  --with-stream_geoip_module \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-threads \
  "

COPY ./patches /patches

RUN \
  echo "Apply nginx patches ..." \
  && cd /usr/src/nginx-$NGINX_COMMIT \
  && echo "apply ngx_http_error_tail.patch" && cat /patches/nginx/ngx_http_error_tail.patch && git apply /patches/nginx/ngx_http_error_tail.patch

RUN \
  echo "Calculate MAKE_JOBS ..." \
  && MAKE_JOBS=$(nproc) \
  # Reduce jobs by 4 if there are more then 7 cores or else set jobs to half of core count
  && if [ "$MAKE_JOBS" -ge 8 ]; then export MAKE_JOBS=$(( $MAKE_JOBS - 4 )); else export MAKE_JOBS=$(( $MAKE_JOBS / 2 )); fi \
  # Set jobs to 1 if calculated value is less then 1
  && if [ "$MAKE_JOBS" -lt 1 ]; then export MAKE_JOBS=1; fi \
  # Set jobs back to result of nproc if BUILD_THROTTLE is not requested
  && if [[ "$BUILD_THROTTLE" != "y" ]]; then export MAKE_JOBS=$(nproc); fi \
  && echo "Make job count: $MAKE_JOBS" \
  # Building nginx
  && echo "Building nginx ($NGINX_VERSION) ..." \
  && cd /usr/src/nginx-${NGINX_COMMIT} \
  # cc and ld opts from official fedora builds
  && export CFLAGS="-O2 -flto=auto -ffat-lto-objects -fexceptions -g -grecord-gcc-switches -pipe -Wall -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -Wp,-D_GLIBCXX_ASSERTIONS -specs=/usr/lib/rpm/redhat/redhat-hardened-cc1 -fPIC -fstack-protector-strong -specs=/usr/lib/rpm/redhat/redhat-annobin-cc1  -m64  -mtune=generic -fasynchronous-unwind-tables -fstack-clash-protection -fcf-protection" \
  && export CXXFLAGS="$CFLAGS" \
  && export LDFLAGS="-fPIC -Wl,-z,relro -Wl,--as-needed  -Wl,-z,now -specs=/usr/lib/rpm/redhat/redhat-hardened-ld -specs=/usr/lib/rpm/redhat/redhat-annobin-cc1  -Wl,--build-id=sha1" \
  && ./auto/configure $CONFIG \
    --with-cc-opt="$CFLAGS" \
    --with-ld-opt="$LDFLAGS" || cat objs/autoconf.err \
  && make -j$MAKE_JOBS \
  && make install

RUN \
  cd /usr/src/nginx-${NGINX_COMMIT} \
  && echo "strip /usr/bin/nginx ..." \
  && strip /usr/bin/nginx \
  # && strip /usr/lib/nginx/modules/*.so
  && echo "Scan for reqired runtime libs ..." \
  # && ldd /usr/lib/nginx/modules/*.so \
  && LIBS=$(ldd /usr/bin/nginx $REQUIRED_TOOLS_IN_DIST_IMAGE | awk '{print $3}' | grep -v '^$' | sort -u) \
  && for LIB_PATH in $LIBS; do echo "Found reqired lib at: $LIB_PATH"; mkdir -pv $(dirname "/tmp/needed_libs$LIB_PATH"); cp -v "$LIB_PATH" "/tmp/needed_libs$LIB_PATH"; done \
  # required for .so file lookups by dynamic linked executables
  && cp -v /lib64/ld-linux-x86-64.so.2 /tmp/needed_libs/lib64/ \
  && echo "strip /tmp/needed_libs/lib64/* ..." \
  && strip /tmp/needed_libs/lib64/*

FROM base-os AS dist-os

ARG REQUIRED_TOOLS_IN_DIST_IMAGE

COPY src/etc/group src/etc/passwd src/etc/shadow /etc/
COPY --from=build /usr/bin/nginx /tmp/scratch/usr/bin/
COPY --from=build /tmp/needed_libs /tmp/needed_libs
# COPY --from=build /usr/lib/nginx/modules/ /usr/lib/nginx/modules/
COPY --from=build /etc/nginx /etc/nginx
COPY src/etc/nginx/ /etc/nginx
COPY config/ /etc/nginx

RUN \
  # remove unused default nginx config files
  rm -v /etc/nginx/*.default \
  # link to nginx modules
  && ln -sv /usr/lib/nginx/modules /etc/nginx/modules \
  # forward error logs to docker log collector
  && mkdir -pv /var/log/nginx \
  && touch /var/log/nginx/access.log /var/log/nginx/error.log \
  && ln -sfv /dev/stdout /var/log/nginx/error.log \
  && ln -sfv /dev/stdout /var/log/nginx/access.log \
  # prepare new filesystem structure for next build stage
  && mkdir -pv /tmp/scratch/bin \
  && mkdir -pv /tmp/scratch/docker-entrypoint.d \
  && mkdir -pv /tmp/scratch/etc/nginx/njs \
  && mkdir -pv /tmp/scratch/etc/nginx/ssl \
  && mkdir -pv /tmp/scratch/etc/ssl/certs \
  && mkdir -pv /tmp/scratch/tmp \
  && mkdir -pv /tmp/scratch/usr/bin \
  && mkdir -pv /tmp/scratch/usr/lib/nginx/modules \
  && mkdir -pv /tmp/scratch/usr/share \
  && mkdir -pv /tmp/scratch/var/cache/nginx/client_temp \
  && mkdir -pv /tmp/scratch/var/cache/nginx/fastcgi_temp \
  && mkdir -pv /tmp/scratch/var/cache/nginx/proxy_temp \
  && mkdir -pv /tmp/scratch/var/cache/nginx/scgi_temp \
  && mkdir -pv /tmp/scratch/var/cache/nginx/uwsgi_temp \
  && mkdir -pv /tmp/scratch/var/log/nginx \
  && mkdir -pv /tmp/scratch/var/run/nginx \
  && mkdir -pv /tmp/scratch/var/www/html \
  && touch /tmp/scratch/etc/nginx/njs.conf \
  && cp -rv /tmp/needed_libs/* /tmp/scratch/ \
  && cp -rv /etc/nginx /tmp/scratch/etc/ \
  && cp -rv /usr/share/zoneinfo /tmp/scratch/usr/share/ \
  && cp -v $REQUIRED_TOOLS_IN_DIST_IMAGE /tmp/scratch/bin/ \
  && cp -v /etc/group /tmp/scratch/etc/ \
  && cp -v /etc/passwd /tmp/scratch/etc/ \
  && cp -v /etc/shadow /tmp/scratch/etc/ \
  && cp -v /etc/ssl/certs/ca-certificates.crt /tmp/scratch/etc/ssl/certs/ \
  && mv -v /var/log/nginx /tmp/scratch/var/log/ \
  && rm -rv /tmp/scratch/etc/nginx/html \
  && chmod -v 1777 /tmp/scratch/tmp \
  && chmod +x -v /tmp/scratch/lib64/*.so*

COPY webroot/test.html* /tmp/scratch/var/www/html/
RUN cd /tmp/scratch/var/www/html/ && mv -v test.html index.html && mv -v test.html.gz index.html.gz && mv -v test.html.br index.html.br
COPY src/docker-entrypoint.sh /tmp/scratch/
COPY src/docker-entrypoint.d/* /tmp/scratch/docker-entrypoint.d/

RUN \
  cd /tmp/scratch \
  # && echo "Compressing binaries using upx ..." \
  # && upx --best --lzma usr/bin/* bin/* \
  && echo "Create symlinks from /lib -> /lib64 ..." \
  && ln -s lib64 lib

FROM scratch
ENV DNS_RESOLVER="1.1.1.1"
ENV NGINX_ENVSUBST_TEMPLATE_SUFFIX=".conf"
ENV NGINX_LOG_FORMAT_NAME="main"
ENV NGINX_SERVER_HEADER=""
ENV NGINX_WORKER_PROCESSES="auto"
ENV TZ="UTC"
ENV USER_ID="101"
ENV GROUP_ID="101"

COPY --from=dist-os /tmp/scratch /

USER root
EXPOSE 80 443
STOPSIGNAL SIGQUIT

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/nginx", "-g", "daemon off;"]

