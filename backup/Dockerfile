# restic + rclone: restic ходит на Яндекс Диск через rclone
FROM restic/restic:0.19.1
COPY --from=rclone/rclone:1.75.1 /usr/local/bin/rclone /usr/bin/rclone
