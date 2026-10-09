# Multi-stage Dockerfile for Flutter Web Deployment
FROM nginx:alpine

# Copy built web artifacts to nginx web root
COPY build/web /usr/share/nginx/html

# Copy custom nginx configuration for SPA routing
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
