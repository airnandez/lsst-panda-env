# lsst-panda-env

This repository contains tools for building and deploying the PanDA pilot
environment for Rubin under the CernVM-FS repository `/cvmfs/sw.lsst.eu`.

The PanDA tools are installed from releases available in the repository at
https://github.com/lsst-dm/panda-conf.

Given that `panda_env` depends on some non-relocatable components (e.g. `conda`)
and that we don't build in the CernVM-FS stratum zero host, we need tools
to build in an environment which mimics the target deploy environment.

## Usage

### build

To build the scripts in this repository you need a host (either bare metal or
virtual machine) where Docker is installed, has outbound network connectivity
and enough storage to store the products of the build process.

Use `build.sh` to build a release prepared for deployment. To get usage
details use:

```
build.sh -h
```

For instance, to build release `v0.0.2` of `panda_env` do:

```
build.sh -v 0.0.2
```

The build process includes uploading the resulting image by calling the
`upload.sh` script. You can customize it to upload to your preferred destination.

### deploy

Use `deploy.sh` to deploy a release under `/cvmfs/sw.lsst.eu`. To get usage
details use:

```
deploy.sh -h
```

To deploy release `v0.0.2` as prepared by `build.sh` do:

```
deploy.sh -v 0.0.2
```

The specified release will be deployed under:

```
/cvmfs/sw.lsst.eu/linux-x86_64/panda_env/v0.0.2
```

You must run this command in a CernVM-FS stratum 0 of the
repository `/cvmfs/sw.lsst.eu`.

## Sources

This repository is located at [https://github.com/airnandez/lsst-panda-env](https://github.com/airnandez/lsst-panda-env)

## Author

These tools were developed and are maintained by Fabio Hernandez
at [IN2P3 / CNRS computing center](http://cc.in2p3.fr) (Lyon, France).

## License
Copyright 2022 Fabio Hernandez

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
