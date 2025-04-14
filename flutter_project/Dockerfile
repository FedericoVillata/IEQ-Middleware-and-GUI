FROM nginx:alpine

# Remove default Nginx site
RUN rm -rf /usr/share/nginx/html/*

# Copy your Flutter web app files
COPY build/web /usr/share/nginx/html

# Expose port 80 for the web server
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
