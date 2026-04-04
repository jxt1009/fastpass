FROM nginx:1.27-alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/conf.d/fasttrack-web.conf
COPY html/ /usr/share/nginx/html/

EXPOSE 80
