# Varnish on alpine

Based on this [blog post](https://kruyt.org/varnish-kuberenets/).

## Docker Hub

[Image published on Docker Hub](https://hub.docker.com/r/digitalist/varnish-alpine)

## Configurable variables


| ENV variable | default value |
| --- | --- |
| `VARNISH_VERSION` | 7.1.1-r0 |
| `VARNISH_PORT` | 80 |
| `VARNISHD_PARAMS` | '-p default_ttl=3600 -p default_grace=3600' |
| `CACHE_SIZE` | 128m |
| `SECRET_FILE` | /etc/varnish/secret |
| `VCL_CONFIG` | /etc/varnish/default.vcl |

`VARNISH_VERSION` is only valid when building the image.

## Example for Kubernetes deployment

First create a random secret for Varnish:

```bash
kubectl create secret generic varnish-secret --from-literal=secret=$(head -c32 /dev/urandom  | base64)

```

Then deploy a VCL (see example down for Drupal)

And then the deployment it self:


```yaml
apiVersion: v1
kind: Service
metadata:
  name: varnish-svc
  namespace: mynamespace
spec:
  ports:
  - name: "http"
    port: 80
  selector:
    app: varnish-proxy
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: varnish-proxy
  namespace: mynamespace
spec:
  replicas: 2
  selector:
    matchLabels:
      app: varnish-proxy
  template:
    metadata:
      name: varnish-proxy
      labels:
        app: varnish-proxy
    spec:
      volumes:
        - name: varnish-config
          configMap:
            name: varnish-vcl
            items:
              - key: default.vcl
                path: default.vcl
        - name: varnish-secret
          secret:
            secretName: varnish-secret
      containers:
      - name: varnish
        resources:
          limits: 
            memory: 1024Mi
            cpu: 850m
          requests:
            memory: 256Mi
            cpu: 10m 
        image: digitalist/varnish-alpine:latest
        imagePullPolicy: Always
        env:
        - name: CACHE_SIZE
          value: 800m
        - name: VCL_CONFIG
          value: /etc/varnish/configmap/default.vcl
        - name: SECRET_FILE
          value: /etc/varnish/k8s-secret/secret
        - name: VARNISHD_PARAMS
          value: -p default_ttl=3600 -p default_grace=3600 -p http_max_hdr=8192 -p http_resp_hdr_len=32k  -p http_req_hdr_len=32k  -p workspace_client=8192k  -p workspace_backend=8192k  -p http_req_size=104857600 -p http_resp_size=104857600
        volumeMounts:
          - name: varnish-config
            mountPath: /etc/varnish/configmap
          - name: varnish-secret
            mountPath: /etc/varnish/k8s-secret
        ports:
        - containerPort: 80

```

VCL example for Drupal

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: varnish-vcl
data:
  default.vcl: |
    vcl 4.0;

    import directors;
    import std;

    backend one_dev {
            .host = "my-site1-svc";
            .port = "80";
            .first_byte_timeout = 30s;
            .between_bytes_timeout = 30s;
            .connect_timeout = 10s;
    }

    backend two_dev {
            .host = "my-site1-svc";
            .port = "80";
            .first_byte_timeout = 30s;
            .between_bytes_timeout = 30s;
            .connect_timeout = 10s;
    }

    // acl purge {
    //    # ACL we'll use to allow purges
    //     "localhost";
    //     "192.0.0.0"/8;
    //     "172.0.0.0"/8;
    // }

    sub vcl_recv {
      if (req.http.host == "mysite1.dev") {
            set req.backend_hint = one_dev;
        }
        if (req.http.host == "mysite2.dev") {
            set req.backend_hint = two_dev;
        }


        # Added from https://github.com/ihor-sviziev/magento2/blob/f2483b5b679c60d63bb02848e015e7379aeb7e78/app/code/Magento/PageCache/etc/varnish4.vcl
        # Remove all marketing get parameters to minimize the cache objects
        if (req.url ~ "(\?|&)(gclid|cx|ie|cof|siteurl|zanpid|origin|mc_[a-z]+|utm_[a-z]+)=") {
          set req.url = regsuball(req.url, "(gclid|cx|ie|cof|siteurl|zanpid|origin|mc_[a-z]+|utm_[a-z]+)=[-_A-z0-9+()%.]+&?", "");
          set req.url = regsub(req.url, "[?|&]+$", "");
        }

        # Local  BANS and PURGES come in on port 80. They MUST come before AUTH and the HTTPS redirect

        
        # Only allow PURGE requests from IP addresses in the 'purge' ACL.
        if (req.method == "PURGE") {
           # if (!client.ip ~ purge) {
           #     return (synth(405, "Not allowed."));
           # }
            return (hash);
        }

        # Only allow BAN requests from IP addresses in the 'purge' ACL.
        if (req.method == "BAN") {
            # Same ACL check as above:
          # if (!client.ip ~ purge) {
          #     return (synth(403, "Not allowed."));
          # }

            # Logic for the ban, using the Cache-Tags header.
            if (req.http.Cache-Tags) {
                ban("obj.http.Cache-Tags ~ " + req.http.Cache-Tags);
            }
            else {
                return (synth(403, "Cache-Tags header missing."));
            }

            # Throw a synthetic page so the request won't go to the backend.
            return (synth(200, "Ban added."));
        }


        # Redirect anything else to HTTPS. Nginx sets "X-Forwarded-Proto"    

        if (req.http.X-Forwarded-Proto == "https") {
            set req.http.X-Forwarded-For = req.http.X-Real-IP;
        } else {
            return(synth(750, "https://" + req.http.Host + req.url));
        }
        
        ### Domain redirects here
        
        # IF request for outlook auto-configure: 404 it rite nau!
        if (req.url == "/autodiscover/autodiscover.xml" ) {
            return(synth(404, "Not Found" ));
        }    

      
        # If we do not unset this, varnish will always pass through the cache
        unset req.http.Authorization;
 
        if (req.url ~ "\.(mp3|mp4)$") {
            return (pass);
        }


        # Pass through any administrative or AJAX-related paths.
        # Note Drupal 8 ajax format: "wrapper_format=drupal_ajax"....
        if (req.url ~ "^/status\.php$" ||
            req.url ~ "^/update\.php$" ||
            req.url ~ "^/update\.php$" ||
            req.url ~ "^/admin$" ||
            req.url ~ "^/admin/.*$" ||
            req.url ~ "^/flag/.*$" ||
            req.url ~ "^.*/ajax/.*$" ||
            req.url ~ "^.*/ahah/.*$" ||
            req.url ~ "^/system/files/.*$" ||
            req.url ~ "^.*wrapper_format=drupal_ajax.*$") {
              return (pass);
        }

        # Removing cookies for static content so Varnish caches these files.
        if (req.url ~ "(?i)\.(pdf|asc|dat|txt|doc|xls|ppt|tgz|csv|png|gif|jpeg|jpg|ico|swf|css|js)(\?.*)?$") {
            unset req.http.Cookie;
        }

        # Remove all cookies that Drupal doesn't need to know about. We explicitly
        # list the ones that Drupal does need, the SESS and NO_CACHE. If, after
        # running this code we find that either of these two cookies remains, we
        # will pass as the page cannot be cached.
        if (req.http.Cookie) {
            # 1. Append a semi-colon to the front of the cookie string.
            # 2. Remove all spaces that appear after semi-colons.
            # 3. Match the cookies we want to keep, adding the space we removed
            #    previously back. (\1) is first matching group in the regsuball.
            # 4. Remove all other cookies, identifying them by the fact that they have
            #    no space after the preceding semi-colon.
            # 5. Remove all spaces and semi-colons from the beginning and end of the
            #    cookie string.
            set req.http.Cookie = ";" + req.http.Cookie;
            set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
            set req.http.Cookie = regsuball(req.http.Cookie, ";(SESS[a-z0-9]+|SSESS[a-z0-9]+|NO_CACHE+|basic_auth)=", "; \1=");
            set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
            set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

            if (req.http.Cookie == "") {
                # If there are no remaining cookies, remove the cookie header. If there
                # aren't any cookie headers, Varnish's default behavior will be to cache
                # the page.
                unset req.http.Cookie;
            }
            else {
                # If there is any cookies left (a session or NO_CACHE cookie), do not
                # cache the page. Pass it on to Apache directly.
                return (pass);
            }
        }
    }

    sub vcl_synth {
      if (resp.status == 750) {
        set resp.http.Location = resp.reason;
        set resp.status = 301;
        return(deliver);
      }
    }

    # Set a header to track a cache HITs and MISSes.
    sub vcl_deliver {

        # Remove ban-lurker friendly custom headers when delivering to client.
        unset resp.http.X-Url;
        unset resp.http.X-Host;
        # Comment these for easier Drupal cache tag debugging in development.
        unset resp.http.Cache-Tags;
        unset resp.http.cache-tags;
        unset resp.http.x-drupal-cache-contexts;
        unset resp.http.x-drupal-cache-tags;

        #unset resp.http.X-Drupal-Cache-Contexts;

        if (obj.hits > 0) {
            set resp.http.Cache-Tags = "HIT";
        }
        else {
            set resp.http.Cache-Tags = "MISS";
        }
        
        # Possible fix for problem with duplicates of the x-content-type-options
        if (resp.http.X-Content-Type-Options && resp.http.X-Content-Type-Options == "nosniff") {
          unset resp.http.X-Content-Type-Options;
            set resp.http.X-Content-Type-Options = "nosniff";
        }
    }

    # Instruct Varnish what to do in the case of certain backend responses (beresp).
    sub vcl_backend_response {

        if (beresp.http.Surrogate-Control ~ "BigPipe/1.0") {
          set beresp.do_stream = true;
          set beresp.ttl = 0s;
        }
        # Set ban-lurker friendly custom headers.
        set beresp.http.X-Url = bereq.url;
        set beresp.http.X-Host = bereq.http.host;

        # Cache 404s, 301s, at 500s with a short lifetime to protect the backend.
        if (beresp.status == 404 || beresp.status == 301 || beresp.status == 500) {
            set beresp.ttl = 10m;
        }

        # Don't allow static files to set cookies.
        # (?i) denotes case insensitive in PCRE (perl compatible regular expressions).
        # This list of extensions appears twice, once here and again in vcl_recv so
        # make sure you edit both and keep them equal.
        if (bereq.url ~ "(?i)\.(pdf|asc|dat|txt|doc|xls|ppt|tgz|csv|png|gif|jpeg|jpg|ico|swf|css|js)(\?.*)?$") {
            unset beresp.http.set-cookie;
        }

        # Allow items to remain in cache up to 6 hours past their cache expiration.
        set beresp.grace = 6h;
    }


    sub vcl_hit {
      if (req.http.Authorization) {
        # Not cacheable by default
        return (pass);
      }
    }


```

Then you need to setup so that the ingress goes to varnish:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: mynamespace

spec:
  rules:
    - host: mysite1.dev
      http:
        paths:
          - backend:
              service:
                name: varnish-svc
                port: 
                  number: 80
            path: /      
            pathType: Prefix

    - host: mysite2.dev
      http:
        paths:
          - backend:
              service:
                name: varnish-svc
                port: 
                  number: 80
            path: /      
            pathType: Prefix


```
