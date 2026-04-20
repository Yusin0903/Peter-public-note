---
sidebar_position: 2
---

# Docker Tips & Gotchas

## Cleaning Up Resources

Delete all unused resources (images, containers, volumes, networks, build cache):

```bash
docker system prune -a
```

Also clean up volumes:

```bash
docker system prune -a --volumes
```

## NVIDIA GPU Configuration

When specifying NVIDIA GPU in Docker Compose, always include `driver: nvidia`. Without it, newer drivers (550+) will throw errors:

```yaml
# Correct
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]

# Without driver (breaks on NVIDIA driver 550+)
deploy:
  resources:
    reservations:
      devices:
        - capabilities: [gpu]
```

| NVIDIA Driver Version | Behavior Without `driver` |
|-----------------------|--------------------------|
| 535 | Auto-detects correctly |
| 550+ | Throws error — must explicitly specify `driver: nvidia` |

## Video Playback on Jetson

On Jetson devices, you may see "no compatible media can play" in Firefox.

The cause is Jetson's Firefox not supporting certain H.264 codec profiles. Solutions:
- Re-encode with ffmpeg using `baseline` profile: `-profile:v baseline`
- Or use Chromium instead
