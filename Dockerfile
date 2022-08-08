# vim: sw=2 et

ARG ALPINE_VERSION
ARG BUSYBOX_VERSION

FROM alpine:${ALPINE_VERSION} AS build

ARG BORINGSSL_COMMIT
ARG CFLAGS_ADD
ARG HEADERS_MORE_VERSION
ARG NGINX_COMMIT
ARG NGINX_VERSION
ARG NGX_BROTLI_COMMIT
ARG NJS_COMMIT
ARG ZLIB_VERSION

RUN \
  env | sort

RUN \
  apk add --no-cache \
    autoconf \
    automake \
    cmake \
    curl \
    g++ \
    gcc \
    gd-dev \
    geoip-dev \
    git \
    gnupg \
    go \
    libc-dev \
    libtool \
    # libxml2-dev \
    # libxslt-dev \
    linux-headers \
    make \
    mercurial \
    musl-dev \
    ninja \
    openssl-dev \
    pcre2-dev \
    perl-dev \
    upx \
    zlib-dev

WORKDIR /usr/src/

RUN \
  echo "Cloning nginx $NGINX_VERSION (rev $NGINX_COMMIT from 'quic' branch) ..." \
  && hg clone -b quic --rev $NGINX_COMMIT https://hg.nginx.org/nginx-quic /usr/src/nginx-$NGINX_VERSION

RUN \
  echo "Cloning brotli (rev $NGX_BROTLI_COMMIT) ..." \
  && mkdir /usr/src/ngx_brotli \
  && cd /usr/src/ngx_brotli \
  && git init \
  && git remote add origin https://github.com/google/ngx_brotli.git \
  && git fetch --depth 1 origin $NGX_BROTLI_COMMIT \
  && git checkout --recurse-submodules -q FETCH_HEAD \
  && git submodule update --init --depth 1

RUN \
  echo "Cloning boringssl (rev $BORINGSSL_COMMIT) ..." \
  && cd /usr/src \
  && git clone https://github.com/google/boringssl \
  && cd boringssl \
  && git checkout $BORINGSSL_COMMIT

RUN \
  echo "Building boringssl ..." \
  && cd /usr/src/boringssl \
  && mkdir build \
  && cd build \
  && CMAKE_BUILD_PARALLEL_LEVEL=$(nproc) \
  # Reduce jobs by 4 if there are more then 7 cores else set jobs to half of core count
  && if [ "$CMAKE_BUILD_PARALLEL_LEVEL" -ge 8 ]; then export CMAKE_BUILD_PARALLEL_LEVEL=$(( $CMAKE_BUILD_PARALLEL_LEVEL - 4 )); else export CMAKE_BUILD_PARALLEL_LEVEL=$(( $CMAKE_BUILD_PARALLEL_LEVEL / 2 )); fi \
  && cmake -GNinja .. \
  && ninja -j$CMAKE_BUILD_PARALLEL_LEVEL

RUN \
  echo "Downloading headers-more-nginx-module (rev $HEADERS_MORE_VERSION) ..." \
  && cd /usr/src \
  && wget https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${HEADERS_MORE_VERSION}.tar.gz -O headers-more-nginx-module.tar.gz \
  && tar -xf headers-more-nginx-module.tar.gz

RUN \
  echo "Downloading njs-nginx-module (rev $NJS_COMMIT) ..." \
  && cd /usr/src \
  && hg clone --rev $NJS_COMMIT http://hg.nginx.org/njs /usr/src/njs-nginx-module-$NJS_COMMIT

RUN \
  echo "Downloading zlib (version $ZLIB_VERSION) ..." \
  && cd /usr/src \
  && wget https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz -O zlib-${ZLIB_VERSION}.tar.gz \
  && tar -xf zlib-${ZLIB_VERSION}.tar.gz

# https://hg.nginx.org/nginx-quic/file/quic/README#l72
ARG CONFIG="\
  # --with-http_image_filter_module \
  # --with-http_xslt_module \
  --add-module=/usr/src/headers-more-nginx-module-$HEADERS_MORE_VERSION \
  --add-module=/usr/src/ngx_brotli \
  --add-module=/usr/src/njs-nginx-module-$NJS_COMMIT/nginx \
  --build=quic-$NGINX_COMMIT-boringssl-$BORINGSSL_COMMIT \
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
  --with-http_v3_module \
  --with-pcre \
  --with-pcre-jit \
  --with-stream \
  --with-stream_geoip_module \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-threads \
  --with-zlib=/usr/src/zlib-$ZLIB_VERSION \
  --without-mail_imap_module \
  --without-mail_pop3_module \
  --without-mail_smtp_module \
  "

RUN \
  echo "Building nginx (v$NGINX_VERSION)..." \
  && cd /usr/src/nginx-$NGINX_VERSION \
  && ./auto/configure $CONFIG \
    --with-cc-opt="$CFLAGS_ADD -I../boringssl/include" \
    --with-ld-opt="-s -static -L../boringssl/build/ssl \
           -L../boringssl/build/crypto" \
  && MAKE_JOBS=$(nproc) \
  # Reduce jobs by 4 if there are more then 7 cores else set jobs to half of core count
  && if [ "$MAKE_JOBS" -ge 8 ]; then export MAKE_JOBS=$(( $MAKE_JOBS - 4 )); else export MAKE_JOBS=$(( $MAKE_JOBS / 2 )); fi \
  && echo "Make job count: $MAKE_JOBS" \
  && make -j$MAKE_JOBS

RUN \
  cd /usr/src/nginx-$NGINX_VERSION \
  && make install \
  && rm -rf /etc/nginx/html/ \
  && mkdir /etc/nginx/conf.d/ \
  # && strip /usr/lib/nginx/modules/*.so
  && strip /usr/bin/nginx* \
  && upx --best --lzma /usr/bin/nginx*

FROM alpine:${ALPINE_VERSION} AS build-renvsubst
RUN \
  apk add --no-cache curl upx git musl-dev gcc \
  && cd ~ \
  && curl --proto '=https' --tlsv1.3 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly \
  && source .cargo/env \
  && rustup component add rust-src --toolchain nightly \
  && git clone https://github.com/CompileNix/renvsubst \
  && cd renvsubst \
  && cargo +nightly build -Z build-std=std,panic_abort -Z build-std-features=panic_immediate_abort --target x86_64-unknown-linux-musl --release \
  && upx --best --lzma target/x86_64-unknown-linux-musl/release/renvsubst \
  && cp -v target/x86_64-unknown-linux-musl/release/renvsubst /envsubst

FROM busybox:${BUSYBOX_VERSION}-musl AS busybox

FROM alpine:${ALPINE_VERSION} AS alpine-base

COPY src/etc/group src/etc/passwd src/etc/shadow /etc/
# COPY --from=build /usr/lib/nginx/modules/ /usr/lib/nginx/modules/
COPY --from=build /etc/nginx /etc/nginx
COPY --from=build-renvsubst /envsubst /usr/bin/
COPY src/etc/nginx/nginx.conf /etc/nginx
COPY config/ /etc/nginx

RUN \
  apk add --no-cache upx tree \
  # remove unused default nginx config files
  && rm -v /etc/nginx/*.default \
  # link to nginx modules
  && ln -sv /usr/lib/nginx/modules /etc/nginx/modules \
  # forward error logs to docker log collector
  && mkdir -pv /var/log/nginx \
  && touch /var/log/nginx/access.log /var/log/nginx/error.log \
  && ln -sfv /dev/stdout /var/log/nginx/error.log \
  && ln -sfv /dev/stdout /var/log/nginx/access.log \
  # prepare new filesystem structure for next build stage
  && mkdir -pv /tmp/scratch/docker-entrypoint.d \
  && mkdir -pv /tmp/scratch/etc/nginx/ssl \
  && mkdir -pv /tmp/scratch/etc/ssl/certs \
  && mkdir -pv /tmp/scratch/tmp \
  && mkdir -pv /tmp/scratch/usr/bin \
  && mkdir -pv /tmp/scratch/usr/lib/nginx/modules \
  && mkdir -pv /tmp/scratch/var/cache/nginx/client_temp \
  && mkdir -pv /tmp/scratch/var/cache/nginx/fastcgi_temp \
  && mkdir -pv /tmp/scratch/var/cache/nginx/proxy_temp \
  && mkdir -pv /tmp/scratch/var/cache/nginx/scgi_temp \
  && mkdir -pv /tmp/scratch/var/cache/nginx/uwsgi_temp \
  && mkdir -pv /tmp/scratch/var/log/nginx \
  && mkdir -pv /tmp/scratch/var/run/nginx \
  && mkdir -pv /tmp/scratch/var/www/html \
  && cp -rv /etc/group /tmp/scratch/etc/ \
  && cp -rv /etc/nginx /tmp/scratch/etc/ \
  && cp -rv /etc/passwd /tmp/scratch/etc/ \
  && cp -rv /etc/shadow /tmp/scratch/etc/ \
  && cp -rv /etc/ssl/certs/ca-certificates.crt /tmp/scratch/etc/ssl/certs/ \
  && cp -v /usr/bin/envsubst /tmp/scratch/usr/bin/ \
  && mv -v /var/log/nginx /tmp/scratch/var/log/ \
  && chown -Rv nginx:nginx /tmp/scratch/etc/nginx \
  && chown -Rv nginx:nginx /tmp/scratch/var/cache/nginx \
  && chown -Rv nginx:nginx /tmp/scratch/var/log/nginx \
  && chown -Rv nginx:nginx /tmp/scratch/var/run/nginx \
  && chmod -v 1777 /tmp/scratch/tmp
COPY src/docker-entrypoint.sh /tmp/scratch/
COPY src/docker-entrypoint.d/envsubst-on-templates.sh /tmp/scratch/docker-entrypoint.d/
COPY --from=busybox /bin/busybox /tmp/scratch/bin/
COPY --from=build /usr/bin/nginx /tmp/scratch/usr/bin/
# link only required cli tools
RUN \
  cd /tmp/scratch/bin \
  && upx --best --lzma busybox \
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
  && ln -sv busybox tail
RUN \
  cd /tmp/scratch \
  && tree -a -F --dirsfirst -A -n .

FROM scratch
ENV DNS_RESOLVER="1.1.1.1"

COPY --from=alpine-base /tmp/scratch/ /
USER nginx
EXPOSE 2080 2443
STOPSIGNAL SIGTERM

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/nginx", "-g", "daemon off;"]

