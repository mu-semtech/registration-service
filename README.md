# Registration microservice
Registration microservice running on [mu.semte.ch](http://mu.semte.ch).

## Integrate registration service in a mu.semte.ch project
Add the following snippet to your `docker-compose.yml` to include the registration service in your project.

```
registration:
  image: semtech/mu-registration-service:2.4.0
  links:
    - database:database
```
        
The triple store used in the backend is linked to the registration service container as `database`. If you configure another SPARQL endpoint URL through `MU_SPARQL_ENDPOINT` update the link name accordingly. Make sure the registration service is able to execute update queries against this store.

To strengthen the password hashing, you can configure an application wide salt through the `MU_APPLICATION_SALT` environment variable. This salt will be concatenated with a salt generated per user to hash the user passwords. By default the application wide salt is not set. If you configure this salt, make sure to configure the [login microservice](https://github.com/mu-semtech/login-service) with the same salt.

The `MU_AUTO_LOGIN_ON_REGISTRATION` environment variable (default: `false`) specifies whether the new user should be logged in automatically at the end of the registration request.

The `MU_APPLICATION_GRAPH` environment variable (default: `http://mu.semte.ch/application`) specifies the graph in the triple store the login service will work in.

Add rules to the `dispatcher.ex` to dispatch requests to the registration service. E.g. 

```
  match "/accounts/*path" do
    Proxy.forward conn, path, "http://registration/accounts/"
  end
```
The host `registration` in the forward URL reflects the name of the registration service in the `docker-compose.yml` file as defined above.

More information how to setup a mu.semte.ch project can be found in [mu-project](https://github.com/mu-semtech/mu-project).


## Available requests

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
    attributes: {
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
    attributes: {
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
