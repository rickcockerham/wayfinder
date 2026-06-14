rake assets:clean
rake assets:precompile
chown -R deploy:deploy public/assets

service wayfinder restart
