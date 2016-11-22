# Concourse Bitbucket Pipelines Discovery Resource

Concourse resource to scan a Bitbucket project (repositories/branches) to setup pipelines configuration which
can be included by other resources such as [Concourse Pipelines Sync Resource](https://github.com/laurentverbruggen/concourse-pipelines-sync-resource).
Advantage is that developers could setup a single pipeline which is able to automatically
add pipelines for all repositories in that project.
Pipeline configuration can then be included in the same repository instead of a different one.
For now only basic authentication is supported.

## Installing

Use this resource by adding the following to the `resource_types` section of a pipeline config:

```yaml
---
resource_types:
- name: concourse-bitbucket-pipelines-discovery
  type: docker-image
  source:
    repository: laurentverbruggen/concourse-bitbucket-pipelines-discovery-resource
```

See [concourse docs](http://concourse.ci/configuring-resource-types.html) for more details
on adding `resource_types` to a pipeline config.

## Source Configuration

* `host`: *Required.* Host of the Bitbucket server e.g. `http://git-scm.com/`

* `project`: *Required.* Bitbucket project to scan for repositories.

* `username`: *Optional.* Username for HTTP(S) auth when pulling/pushing.
  This is needed when only HTTP/HTTPS protocol for git is available (which does not support private key auth)
  and auth is required.

* `password`: *Optional.* Password for HTTP(S) auth when pulling/pushing.

* `repository`: *Optional.* Regular expression to determine which repositories from the project will be considered.
Pattern is determined by [egrep](http://linuxcommand.org/man_pages/egrep1.html).
If nothing is specified all repositories from the project will be considered.

* `branch`: *Optional.* Regular expression to determine which branches from each repository will be considered.
Pattern is determined by [egrep](http://linuxcommand.org/man_pages/egrep1.html).
If nothing is specified only the default branch for each repository will be considered.

### Example

Resource configuration to scan a project and only include specific repositories/branches:

``` yaml
resources:
- name: bitbucket-discover
  type: concourse-bitbucket-pipelines-discovery
  source:
    host: http://git-scm.com
    project: PROJECT
    username: {{git-username}}
    password: {{git-password}}
    repository: test
    branch: .
```

## Behavior

### `check`: Scan projects.

The Bitbucket project is scanned for repositories and the result is to return a version with a hash of what was found.
If a repository or branch was added the hash will change, else the previous version is returned.
To know when the last change was detected a timestamp is also included in the returned version.

### `in`: Create pipeline configuration for retrieved projects.

Does the same thing as check but here it creates pipeline configuration for every
repository/branch that was discovered.

The pipeline configuration that is created follows the following default template:

```yaml
resource_types:
- name: pipelines-discovery-resource
  type: docker-image
  source:
    repository: laurentverbruggen/concourse-pipelines-discovery-resource
- name: pipelines-sync-resource
  type: docker-image
  source:
    repository: laurentverbruggen/concourse-pipelines-sync-resource

resources:
- name: pipeline-sync
  type: pipelines-sync-resource
  source: {}
- name: %%DISCOVERY_RESOURCE_NAME%%
  type: pipelines-discovery-resource
  source:
    username: %%BITBUCKET_USERNAME%%
    password: %%BITBUCKET_PASSWORD%%

jobs:
  name: %%DISCOVERY_RESOURCE_NAME%%
  build_logs_to_retain: 5
  public: false
  serial: true
  disable_manual_trigger: false
  plan:
  - get: %%DISCOVERY_RESOURCE_NAME%%
    trigger: true
    params: {}
  - put: pipeline-sync
    params:
      config:
        file: %%DISCOVERY_RESOURCE_NAME%%/concourse.json
      sync: true
```

Almost every aspect of this template can be configured using the parameters below.
The template allows 3 placeholders to be used (also in files referenced in parameters):

* `DISCOVERY_RESOURCE_NAME`: matches the name of the repository and, if branch pattern is set in source, it will be appended with the branch name: `<repository>[:<branch>]`
* `BITBUCKET_USERNAME`: Bitbucket username passed in source
* `BITBUCKET_PASSWORD`: Bitbucket password passed in source

#### Parameters

The template from above can be extended (top level is merged) with custom configuration passed as params for this resource.
Every template described below matches a specific part in the default template that can be extended with that parameter:

* `discovery`: extend discovery configuration. This allows you to include other discovery resources than the default.

  * `type`

  ```yaml
    name: pipelines-discovery-resource
    type: docker-image
    source:
      repository: laurentverbruggen/concourse-pipelines-discovery-resource
  ```

  * `resource`

  ```yaml
    name: %%DISCOVERY_RESOURCE_NAME%%
    type: pipelines-discovery-resource
    source:
      username: %%BITBUCKET_USERNAME%%
      password: %%BITBUCKET_PASSWORD%%
  ```

* `sync`: extend sync configuration. This allows you to include other sync resources than the default.

  * `type`

  ```yaml
    name: pipelines-sync-resource
    type: docker-image
    source:
      repository: laurentverbruggen/concourse-pipelines-sync-resource
  ```

  * `resource`

  ```yaml
    name: pipeline-sync
    type: pipelines-sync-resource
    source: {}
  ```

* `job`: extend discovery job configuration. This allows you to tweak the job a little.

  * `config`

  ```yaml
    name: %%DISCOVERY_RESOURCE_NAME%%
    build_logs_to_retain: 5
    public: false
    serial: true
    disable_manual_trigger: false
  ```

  * `get`

  ```yaml
    {}
  ```

  * `put`

  ```yaml
    config:
      file: %%DISCOVERY_RESOURCE_NAME%%/concourse.json
    sync: true
  ```

#### Example

Resource configuration to scan a project and only include specific repositories/branches:

``` yaml
- get: bitbucket-discover
  trigger: true
  params:
    sync:
      resource:
        source:
          username: {{concourse-username}}
          password: {{concourse-password}}
    job:
      params:
        put:
          reference: " (%%BUILD_JOB_NAME%%)"
```

### `out`: No-Op
