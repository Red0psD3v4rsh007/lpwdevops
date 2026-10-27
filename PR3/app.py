import os
import time
import redis
from flask import Flask

app = Flask(__name__)

# Allow Redis host to be configured via environment variable
# Defaults to 'redis' for docker-compose, use 'localhost' for ECS Fargate
REDIS_HOST = os.environ.get('REDIS_HOST', 'redis')
cache = redis.Redis(host=REDIS_HOST, port=6379)

def get_hit_count():
    retries = 5
    while True:
        try:
            return cache.incr('hits')
        except redis.exceptions.ConnectionError as exc:
            if retries == 0:
                raise exc
            retries -= 1
            time.sleep(0.5)

@app.route('/')
def hello():
    count = get_hit_count()
    return f'Hello from AWS ECS! I have been seen {count} times.\n'

@app.route('/health')
def health():
    return {'status': 'healthy', 'service': 'pr4-flask-app'}, 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
