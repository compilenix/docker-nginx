# vim: sw=2 et

ARG ALPINE_VERSION
ARG BUSYBOX_VERSION

FROM busybox:${BUSYBOX_VERSION}-musl AS busybox

FROM alpine:${ALPINE_VERSION} AS build-renvsubst
RUN \
  apk add --no-cache curl upx git musl-dev gcc \
  && cd ~ \
  && curl --proto '=https' --tlsv1.3 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly \
  && source .cargo/env \
  && rustup component add rust-src --toolchain nightly \
  && git clone https://github.com/CompileNix/renvsubst \
  && cd renvsubst \
  && cargo \
    +nightly build \
    -Z build-std=std,panic_abort \
    -Z build-std-features=panic_immediate_abort \
    --target x86_64-unknown-linux-musl \
    --release \
  && upx --best --lzma target/x86_64-unknown-linux-musl/release/cnx-renvsubst \
  && cp -v target/x86_64-unknown-linux-musl/release/cnx-renvsubst /envsubst

FROM alpine:${ALPINE_VERSION} AS build

ARG BUILD_THROTTLE
ARG CFLAGS_ADD
ARG HEADERS_MORE_VERSION
ARG NGINX_COMMIT
ARG NGINX_VERSION
ARG NGX_BROTLI_COMMIT
ARG NJS_COMMIT
ARG NJS_VERSION
ARG OPENSSL_VERSION
ARG PCRE_VERSION
ARG ZLIB_VERSION

RUN \
  env | sort

    # libxml2-dev \
    # libxslt-dev \
RUN \
  apk add --no-cache \
    autoconf \
    automake \
    cmake \
    curl \
    gcc \
    gd-dev \
    geoip-dev \
    git \
    gnupg \
    libc-dev \
    libtool \
    linux-headers \
    make \
    mercurial \
    musl-dev \
    perl-dev \
    upx

WORKDIR /usr/src/

RUN \
  echo "Cloning nginx $NGINX_VERSION (rev $NGINX_COMMIT from 'default' branch) ..." \
  && hg clone -b default --rev $NGINX_COMMIT https://hg.nginx.org/nginx /usr/src/nginx-$NGINX_VERSION

RUN \
  echo "Cloning nginx njs module v${NJS_VERSION} (rev $NJS_COMMIT) ..." \
  && cd /usr/src \
  && hg clone --rev $NJS_COMMIT http://hg.nginx.org/njs /usr/src/njs-nginx-module-${NJS_COMMIT}-${NJS_VERSION}

RUN \
  echo "Cloning brotli module (rev $NGX_BROTLI_COMMIT) ..." \
  && mkdir /usr/src/ngx_brotli \
  && cd /usr/src/ngx_brotli \
  && git init \
  && git remote add origin https://github.com/google/ngx_brotli.git \
  && git fetch --depth 1 origin $NGX_BROTLI_COMMIT \
  && git checkout --recurse-submodules -q FETCH_HEAD \
  && git submodule update --init --depth 1

RUN \
  echo "Downloading headers-more module (rev $HEADERS_MORE_VERSION) ..." \
  && cd /usr/src \
  && wget https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${HEADERS_MORE_VERSION}.tar.gz -O headers-more-nginx-module.tar.gz \
  && tar -xf headers-more-nginx-module.tar.gz

RUN \
  echo "Downloading zlib (version $ZLIB_VERSION) ..." \
  && cd /usr/src \
  && wget https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz -O zlib-${ZLIB_VERSION}.tar.gz \
  && tar -xf zlib-${ZLIB_VERSION}.tar.gz

RUN \
  echo "Downloading OpenSSL (version $OPENSSL_VERSION) ..." \
  && cd /usr/src \
  && wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -O openssl-${OPENSSL_VERSION}.tar.gz \
  && tar -xf openssl-${OPENSSL_VERSION}.tar.gz

RUN \
  echo "Downloading PCRE (version $PCRE_VERSION) ..." \
  && cd /usr/src \
  && wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE_VERSION}/pcre2-${PCRE_VERSION}.tar.gz -O pcre2-${PCRE_VERSION}.tar.gz \
  && tar -xf pcre2-${PCRE_VERSION}.tar.gz

  # --with-http_image_filter_module \
  # --with-http_xslt_module \
ARG CONFIG="\
  --add-module=/usr/src/headers-more-nginx-module-$HEADERS_MORE_VERSION \
  --add-module=/usr/src/ngx_brotli \
  --add-module=/usr/src/njs-nginx-module-$NJS_COMMIT-$NJS_VERSION/nginx \
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
  --with-compat \
  --with-debug \
  --with-file-aio \
  --with-http_addition_module \
  --with-http_auth_request_module \
  --with-http_flv_module \
  --with-http_geoip_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_mp4_module \
  --with-http_random_index_module \
  --with-http_realip_module \
  --with-http_secure_link_module \
  --with-http_slice_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-mail \
  --with-mail_ssl_module \
  --with-openssl=/usr/src/openssl-$OPENSSL_VERSION \
  --with-pcre-jit \
  --with-pcre=/usr/src/pcre2-$PCRE_VERSION \
  --with-stream \
  --with-stream_geoip_module \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-threads \
  --with-zlib=/usr/src/zlib-$ZLIB_VERSION \
  "

COPY ./patches /patches

RUN \
  echo "Apply nginx patches ..." \
  && cd /usr/src/nginx-$NGINX_VERSION \
  && echo "apply ngx_http_error_tail.patch" && cat /patches/nginx/ngx_http_error_tail.patch && git apply /patches/nginx/ngx_http_error_tail.patch

# RUN \
#   echo "Apply zlib patches ..." \
#   && cd /usr/src/zlib-$ZLIB_VERSION \
#   && echo "apply CVE-2022-37434.patch" && cat /patches/zlib/CVE-2022-37434.patch && git apply /patches/zlib/CVE-2022-37434.patch

RUN \
  echo "Building nginx ($NGINX_VERSION)..." \
  && MAKE_JOBS=$(nproc) \
  # Reduce jobs by 4 if there are more then 7 cores else set jobs to half of core count
  && if [ "$MAKE_JOBS" -ge 8 ]; then export MAKE_JOBS=$(( $MAKE_JOBS - 4 )); else export MAKE_JOBS=$(( $MAKE_JOBS / 2 )); fi \
  && if [ "$MAKE_JOBS" -le 1 ]; then export MAKE_JOBS=1; fi \
  # Set jobs back to result of nproc if BUILD_THROTTLE is not requested
  && if [[ "$BUILD_THROTTLE" != "y" ]]; then export MAKE_JOBS=$(nproc); fi \
  && echo "Make job count: $MAKE_JOBS" \
  && cd /usr/src/nginx-$NGINX_VERSION \
  && ./auto/configure $CONFIG \
    --with-cc-opt="$CFLAGS_ADD" \
    --with-openssl-opt="$CFLAGS_ADD" \
    --with-zlib-opt="$CFLAGS_ADD" \
    --with-ld-opt="-static" \
  && make -j$MAKE_JOBS \
  && make install

RUN \
  cd /usr/src/nginx-$NGINX_VERSION \
  # && strip /usr/lib/nginx/modules/*.so
  && strip /usr/bin/nginx \
  && upx --best --lzma /usr/bin/nginx

FROM alpine:${ALPINE_VERSION} AS alpine-base

RUN apk add --no-cache tree tzdata
COPY src/etc/group src/etc/passwd src/etc/shadow /etc/
COPY --from=build-renvsubst /envsubst /tmp/scratch/usr/bin/
COPY --from=busybox /bin/busybox /tmp/scratch/bin/
COPY --from=build /usr/bin/nginx /tmp/scratch/usr/bin/
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
  && mkdir -pv /tmp/scratch/docker-entrypoint.d \
  && mkdir -pv /tmp/scratch/etc/nginx/njs \
  && mkdir -pv /tmp/scratch/etc/nginx/ssl \
  && mkdir -pv /tmp/scratch/etc/ssl/certs \
  && mkdir -pv /tmp/scratch/tmp \
  && mkdir -pv /tmp/scratch/usr/bin \
  && mkdir -pv /tmp/scratch/usr/lib/nginx/modules \
  && mkdir -pv /tmp/scratch/usr/sbin \
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
  && cp -rv /etc/nginx /tmp/scratch/etc/ \
  && cp -rv /usr/share/zoneinfo /tmp/scratch/usr/share/ \
  && cp -v /etc/group /tmp/scratch/etc/ \
  && cp -v /etc/passwd /tmp/scratch/etc/ \
  && cp -v /etc/shadow /tmp/scratch/etc/ \
  && cp -v /etc/ssl/certs/ca-certificates.crt /tmp/scratch/etc/ssl/certs/ \
  && mv -v /var/log/nginx /tmp/scratch/var/log/ \
  && rm -rv /tmp/scratch/etc/nginx/html \
  && chown -Rv nginx:nginx /tmp/scratch/etc/nginx \
  && chown -Rv nginx:nginx /tmp/scratch/var/cache/nginx \
  && chown -Rv nginx:nginx /tmp/scratch/var/log/nginx \
  && chown -Rv nginx:nginx /tmp/scratch/var/run/nginx \
  && chmod -v 1777 /tmp/scratch/tmp
COPY src/docker-entrypoint.sh /tmp/scratch/
COPY src/docker-entrypoint.d/* /tmp/scratch/docker-entrypoint.d/
# link only required cli tools
RUN \
  cd /tmp/scratch/bin \
  # upx on busybox apparently causes: nginx: [emerg] failed to create js VM
  # && upx --best --lzma busybox \
  # some cli tools that are useful for debugging but not in production
  && ln -sv busybox basename \
  && ln -sv busybox cat \
  && ln -sv busybox cp \
  && ln -sv busybox cut \
  && ln -sv busybox dirname \
  && ln -sv busybox echo \
  && ln -sv busybox env \
  && ln -sv busybox find \
  && ln -sv busybox ls \
  && ln -sv busybox mkdir \
  && ln -sv busybox printf \
  && ln -sv busybox rm \
  && ln -sv busybox sh \
  && ln -sv busybox sort \
  && ln -sv busybox stat
RUN \
  cd /tmp/scratch \
  && tree -a -F --dirsfirst -A -n .

FROM scratch
ENV DNS_RESOLVER="1.1.1.1"
ENV NGINX_ENVSUBST_TEMPLATE_SUFFIX=".conf"
ENV NGINX_LOG_FORMAT_NAME="main"
ENV NGINX_SERVER_HEADER=""
ENV NGINX_WORKER_PROCESSES="2"
ENV TZ="UTC"

COPY --from=alpine-base /tmp/scratch/ /
USER nginx
EXPOSE 2080 2443
STOPSIGNAL SIGQUIT

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/nginx", "-g", "daemon off;"]

