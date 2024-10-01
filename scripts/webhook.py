import os
import subprocess
from flask import Flask, request, Response, jsonify


app = Flask(__name__)


@app.route('/trigger-benchmark', methods=['POST'])
def response():
    data = request.get_json()
    if data['ref'] == 'refs/heads/main':
        print("fetching new changes")
        subprocess.run(['git', 'fetch', '--all'], check=True) # pull new changes
        print(f"checking out new changes {data['after']}");
        subprocess.run(['git', 'checkout', data['after']], check=True) # checkout the new changes

        # build the benchmark
        try:
            subprocess.run(f"/home/ubuntu/zig-linux-x86_64-0.13.0/zig build -Doptimize=ReleaseSafe benchmark -- gossip --telemetry={data['after']}", check=True, shell=True)
        except Exception as e:
            print(f"errored: {str(e)}")
            return jsonify({'message': 'An error occurred', 'error': str(e)}), 500
    return Response(status=200)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)