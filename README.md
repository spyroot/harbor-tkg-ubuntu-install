# harbor tkg ubuntu install

TKG, by default, uses the public registry in case you need to install the local Harbor registry for TKG that should help. Note it self signed certs.

* Script idempotent, it regenerates all cert on each run, copies all cert
to Harbor, adjust the default config template, sets a correct path to all cert.

* It copies all required certs to docker /etc/docker/cert.d/registry_host_name and updates docker-compose.

* It finishes Harbor install, add all required docker tag to a local copy of all TKG container images 
and push each image to a local instance of Harbor

* Adjust all .tkg/config.yaml etc files and re-point to new repo

