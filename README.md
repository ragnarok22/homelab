# homelab
HomeLab


## Keep the images updated
Just use [Watchtower](https://github.com/containrrr/watchtower)

    docker run --detach \
        --name watchtower \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        containrrr/watchtower
