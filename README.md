# Registration microservice
Registration microservice running on [mu.semte.ch](http://mu.semte.ch).

## Tutorials
### Add the registration service to a stack

Add the following snippet to your `docker-compose.yml` to include the registration service in your project.

```yaml
registration:
  image: semtech/mu-registration-service:2.6.0
  links:
    - database:database
```

The triple store used in the backend is linked to the registration service container as `database`.

Next, add the following rules to the `dispatcher.ex` to dispatch requests to the registration service. E.g.

```elixir
  match "/accounts/*path", @any do
    Proxy.forward conn, path, "http://registration/accounts/"
  end
```

The host `registration` in the forward URL reflects the name of the registration service in the `docker-compose.yml` file as defined above.

More information how to setup a mu.semte.ch project can be found in [mu-project](https://github.com/mu-semtech/mu-project).

### Generate a new user/account
The registration service provides an interactive script to generate a new user and account using [mu-cli](https://github.com/mu-semtech/mu-cli). Execute the following command, enter the required information and insert the generated data in the triplestore.

```bash
mu script registration generate-account
```

## Reference
### Configuration
The following enviroment variables can be set on the registration service:

- **USERS_GRAPH** : graph in which the person and account resources will be stored. E.g. `http://mu.semte.ch/graphs/users`. Defaults to `http://mu.semte.ch/application`.
- **SESSIONS_GRAPH** : graph in which the session resources will be stored. E.g. `http://mu.semte.ch/graphs/sessions`. Defaults to `http://mu.semte.ch/application`.
- **MU_APPLICATION_SALT** : strengthen the password hashing by configuring an application wide salt. This salt will be concatenated with a salt generated per user to hash the user passwords. By default the application wide salt is not set. If you configure this salt, make sure to configure the [login microservice](https://github.com/mu-semtech/login-service) with the same salt. Setting the salt makes account resources non-shareable with stacks containing a login-service configured with another salt.
- **MU_AUTO_LOGIN_ON_REGISTRATION**: whether a new user should automatically be logged in after a succesful registration request  (default: `false`).

### Model
This section describes the minimal required model for the login service. These models can be enriched with additional properties and/or relations.

The graphs is which the resources are stored, can be configured via environment variables.

#### Used prefixes
| Prefix  | URI                                      |
|---------|------------------------------------------|
| mu      | http://mu.semte.ch/vocabularies/core/    |
| account | http://mu.semte.ch/vocabularies/account/ |
| session | http://mu.semte.ch/vocabularies/session/ |
| foaf    | http://xmlns.com/foaf/0.1/               |
| dct     | http://purl.org/dc/terms/                |

#### Persons
##### Class
`foaf:Person`

##### Properties
| Name     | Predicate      | Range                | Definition                                    |
|----------|----------------|----------------------|-----------------------------------------------|
| name     | `foaf:name`    | `xsd:string`         | Name of the person                            |
| created  | `dct:created`  | `xsd:dateTime`       | Creation date of the person resource          |
| modified | `dct:modified` | `xsd:dateTime`       | Last modification date of the person resource |
| account  | `foaf:account` | `foaf:OnlineAccount` | Account linked to the person                  |

#### Accounts
##### Class
`foaf:OnlineAccount`

##### Properties
| Name        | Predicate          | Range           | Definition                                                                                                                            |
|-------------|--------------------|-----------------|---------------------------------------------------------------------------------------------------------------------------------------|
| accountName | `foaf:accountName` | `xsd:string`    | Account name / nickname                                                                                                               |
| password    | `account:password` | `xsd:string`    | Hashed password of the account                                                                                                        |
| salt        | `account:salt`     | `xsd:string`    | Salt used to hash the password                                                                                                        |
| status      | `account:status`   | `rdfs:Resource` | Status of the account. Only active (`<http://mu.semte.ch/vocabularies/account/status/active>`) accounts are taken into account on login. |
| created  | `dct:created`  | `xsd:dateTime`       | Creation date of the person resource          |
| modified | `dct:modified` | `xsd:dateTime`       | Last modification date of the person resource |

#### Sessions
##### Class
None

##### Properties
| Name    | Predicate         | Range                | Definition                     |
|---------|-------------------|----------------------|--------------------------------|
| account | `session:account` | `foaf:OnlineAccount` | Account related to the session |


### API
#### POST /accounts
Register a new account with the given nickname and password.

##### Request body
```javascript
{
  "data": {
    "type": "accounts",
    "attributes": {
      "name": "John Doe",
      "nickname": "john_doe",
      "password": "secret",
      "password-confirmation": "secret"
    }
  }
}
```

##### Response
###### 201 Created
On successful registration with the newly created account in the response body:

```javascript
{
  "links": {
    "self": "accounts/f6419af0-c90f-465f-9333-e993c43e6cf2"
  },
  "data": {
    "type": "accounts",
    "id": "f6419af0-c90f-465f-9333-e993c43e6cf2",
    "attributes": {
      "name": "John Doe",
      "nickname": "john_doe"
    }
  }
}
```

###### 400 Bad Request
- if session header is missing. The header should be automatically set by the [identifier](https://github.com/mu-semtech/mu-identifier).
- if the request body is invalid.
- if the given nickname already exists.



#### PATCH /accounts/current/changePassword
Change the password of the current account, i.e. the account of the user that is currently logged in.

##### Request body
```javascript
{
  "data": {
    "type": "accounts",
    "id": "current",
    "attributes": {
      "old-password": "secret",
      "new-password": "anotherSecret",
      "new-password-confirmation": "anotherSecret"
    }
  }
}
```

##### Response
###### 204 No Content
On successful update of the account.

###### 400 Bad Request
- if session header is missing. The header should be automatically set by the [identifier](https://github.com/mu-semtech/mu-identifier).
- if the old password is incorrect.
- if new password and new password confirmation do not match.
- if the account is inactive.



#### DELETE /accounts/current
Unregister the current account, i.e. remove the account of the user that is currently logged in.

##### Response
###### 204 No Content
On successful unregistration.

###### 400 Bad Request
If session header is missing or invalid. The header should be automatically set by the [identifier](https://github.com/mu-semtech/mu-identifier).




#### PATCH /accounts/:id
Update the account details of the account with the given id.

##### Request body
```javascript
{
  "data": {
    "type": "accounts",
    "id": "f6419af0-c90f-465f-9333-e993c43e6cf2",
    "attributes": {
      "nickname": "john_doe",
      "password": "anotherSecret"
    }
  }
}
```

##### Response
###### 204 No Content
On successful update of the account.

###### 400 Bad Request
- if the account is inactive.
- if the updated nickname already exists

###### 404 Not Found
If an account with the given id doesn't exist.



#### DELETE /accounts/:id
Unregister the account with the given id. This function will be typically used by a system administrator.
##### Response
###### 204 No Content
On successful unregistration.

###### 404 Not Found
If an account with the given id doesn't exist.
