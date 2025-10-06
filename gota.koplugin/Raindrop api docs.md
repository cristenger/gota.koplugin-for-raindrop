
# Overview

Build and integrate tools and applications to help members manage their bookmarks on Raindrop.io

This is the official documentation for Raindrop.io API. A reference to the functionality our public API provides with detailed description of each API endpoint, parameters, and examples.

Please note that you must [register your application](https://app.raindrop.io/settings/integrations) and authenticate with OAuth when making requests. Before doing so, be sure to read our [Terms & Guidelines](https://developer.raindrop.io/terms) to learn how the API may be used.

### 

[](https://developer.raindrop.io/#format)

Format

API endpoints accept arguments either as url-encoded values for non-POST requests or as json-encoded objects encoded in POST request body with `Content-Type: application/json` header.

Where possible, the API strives to use appropriate HTTP verbs for each action.

Verb

Description

GET

Used for retrieving resources.

POST

Used for creating resources.

PUT

Used for updating resources, or performing custom actions.

DELETE

Used for deleting resources.

This API relies on standard HTTP response codes to indicate operation result. The table below is a simple reference about the most used status codes:

Status code

Description

200

The request was processed successfully.

204

The request was processed successfully without any data to return.

4xx

The request was processed with an error and should not be retried unmodified as they won’t be processed any different by an API.

5xx

The request failed due to a server error, it’s safe to retry later.

All `200 OK` responses have the `Content-type: application/json` and contain a JSON-encoded representation of one or more objects.

Payload of POST requests has to be JSON-encoded and accompanied with `Content-Type: application/json` header.

### 

[](https://developer.raindrop.io/#timestamps)

Timestamps

All timestamps are returned in ISO 8601 format:

Copy

```
YYYY-MM-DDTHH:MM:SSZ
```

### 

[](https://developer.raindrop.io/#rate-limiting)

Rate Limiting

For requests using OAuth, you can make up to 120 requests per minute per authenticated user.

The headers tell you everything you need to know about your current rate limit status:

Header name

Description

X-RateLimit-Limit

The maximum number of requests that the consumer is permitted to make per minute.

RateLimit-Remaining

The number of requests remaining in the current rate limit window.

X-RateLimit-Reset

The time at which the current rate limit window resets in UTC epoch seconds.

Once you go over the rate limit you will receive an error response:

Copy

```
HTTP/1.1 429 Too Many Requests
Status: 429 Too Many Requests
X-RateLimit-Limit: 120
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1392321600 
```

### 

[](https://developer.raindrop.io/#cross-origin-resource-sharing)

CORS

The API supports Cross Origin Resource Sharing (CORS) for AJAX requests. You can read the [CORS W3C recommendation](https://www.w3.org/TR/cors/), or [this intro](http://code.google.com/p/html5security/wiki/CrossOriginRequestSecurity) from the HTML 5 Security Guide.

Here’s a sample request sent from a browser hitting `http://example.com`:

Copy

```
HTTP/1.1 200 OK
Access-Control-Allow-Origin: http://example.com
Access-Control-Expose-Headers: ETag, Content-Type, Accept, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset
Access-Control-Allow-Credentials: true
```

[  
](https://developer.raindrop.io/terms)


# Obtain access token

External applications could obtain a user authorized API token via the OAuth2 protocol. Before getting started, developers need to create their applications in [App Management Console](https://app.raindrop.io/settings/integrations) and configure a valid OAuth redirect URL. A registered Raindrop.io application is assigned a unique `Client ID` and `Client Secret` which are needed for the OAuth2 flow.

This procedure is comprised of several steps, which will be described below.

If you just want to test your application, or do not plan to access any data except yours account you don't need to make all of those steps.

Just go to [App Management Console](https://app.raindrop.io/settings/integrations) and open your application settings. Copy **Test token** and use it as described in [**Make authorized calls**](https://developer.raindrop.io/v1/authentication/calls)**.**

## 

[](https://developer.raindrop.io/v1/authentication/token#step-1-the-authorization-request)

Step 1: The authorization request

`GET` `https://raindrop.io/oauth/authorize`

Direct the user to our authorization URL with specified request parameters. — If the user is not logged in, they will be asked to log in — The user will be asked if he would like to grant your application access to his Raindrop.io data

#### 

[](https://developer.raindrop.io/v1/authentication/token#query-parameters)

Query Parameters

Name

Type

Description

redirect_uri

string

Redirect URL configured in your application setting

client_id

string

The unique Client ID of the Raindrop.io app that you registered

307 Check details in Step 2

[](https://developer.raindrop.io/v1/authentication/token#tab-id-307-check-details-in-step-2)

Copy

![](https://developer.raindrop.io/~gitbook/image?url=https%3A%2F%2F3611960587-files.gitbook.io%2F%7E%2Ffiles%2Fv0%2Fb%2Fgitbook-legacy-files%2Fo%2Fassets%252F-M-GPP1TyNN8gNuijaj7%252F-M-of5es4601IU9HtzYf%252F-M-og97-rwxYlVDTb5mi%252Fauthorize.png%3Falt%3Dmedia%26token%3Dd81cc512-68bb-49a4-9342-f436f1b85c74&width=768&dpr=4&quality=100&sign=cbc9d6&sv=2)

User will be asked if he would like to grant your application access to his Raindrop.io data

Here example CURL request:

Copy

```
curl "https://api.raindrop.io/v1/oauth/authorize?client_id=5e1c382cf6f48c0211359083&redirect_uri=https:%2F%2Foauthdebugger.com%2Fdebug"
```

## 

[](https://developer.raindrop.io/v1/authentication/token#step-2-the-redirection-to-your-application-site)

Step 2: The redirection to your application site

When the user grants your authorization request, the user will be redirected to the redirect URL configured in your application setting. The redirect request will come with query parameter attached: `code` .

The `code` parameter contains the authorization code that you will use to exchange for an access token.

In case of error redirect request will come with `error` query parameter:

Error

Description

access_denied

When the user denies your authorization request

invalid_application_status

When your application exceeds the maximum token limit or when your application is being suspended due to abuse

## 

[](https://developer.raindrop.io/v1/authentication/token#step-3-the-token-exchange)

Step 3: The token exchange

`POST` `https://raindrop.io/oauth/access_token`

Once you have the authorization `code`, you can exchange it for the `access_token` by doing a `POST` request with all required body parameters as JSON:

#### 

[](https://developer.raindrop.io/v1/authentication/token#headers)

Headers

Name

Type

Description

Content-Type

string

application/json

#### 

[](https://developer.raindrop.io/v1/authentication/token#request-body)

Request Body

Name

Type

Description

grant_type

string

**authorization_code**

code

string

Code that you received in step 2

client_id

string

The unique Client ID of the Raindrop.io app that you registered

client_secret

string

Client secret

redirect_uri

string

Same `redirect_uri` from step 1

200

[](https://developer.raindrop.io/v1/authentication/token#tab-id-200)

400 Occurs when code parameter is invalid

[](https://developer.raindrop.io/v1/authentication/token#tab-id-400-occurs-when-code-parameter-is-invalid)

Copy

```
{
  "access_token": "ae261404-11r4-47c0-bce3-e18a423da828",
  "refresh_token": "c8080368-fad2-4a3f-b2c9-71d3z85011vb",
  "expires": 1209599768, //in miliseconds, deprecated
  "expires_in": 1209599, //in seconds, use this instead!!!
  "token_type": "Bearer"
}
```

Here an example CURL request:

Copy

```
curl -X "POST" "https://raindrop.io/oauth/access_token" \
     -H 'Content-Type: application/json' \
     -d $'{
  "code": "c8983220-1cca-4626-a19d-801a6aae003c",
  "client_id": "5e1c589cf6f48c0211311383",
  "redirect_uri": "https://oauthdebugger.com/debug",
  "client_secret": "c3363988-9d27-4bc6-a0ae-d126ce78dc09",
  "grant_type": "authorization_code"
}'
```

## 

[](https://developer.raindrop.io/v1/authentication/token#the-access-token-refresh)

♻️ The access token refresh

`POST` `https://raindrop.io/oauth/access_token`

For security reasons access tokens (except "test tokens") will **expire after two weeks**. In this case you should request the new one, by calling `POST` request with body parameters (JSON):

#### 

[](https://developer.raindrop.io/v1/authentication/token#headers-1)

Headers

Name

Type

Description

Content-Type

string

application/json

#### 

[](https://developer.raindrop.io/v1/authentication/token#request-body-1)

Request Body

Name

Type

Description

client_id

string

The unique Client ID of your app that you registered

client_secret

string

Client secret of your app

grant_type

string

**refresh_token**

refresh_token

string

Refresh token that you get in step 3

200

[](https://developer.raindrop.io/v1/authentication/token#tab-id-200-1)

Copy

```
{
  "access_token": "ae261404-18r4-47c0-bce3-e18a423da898",
  "refresh_token": "c8080368-fad2-4a9f-b2c9-73d3z850111b",
  "expires": 1209599768, //in miliseconds, deprecated
  "expires_in": 1209599, //in seconds, use this instead!!!
  "token_type": "Bearer"
}
```


1. [Rest API v1](https://developer.raindrop.io/v1)
2. [Authentication](https://developer.raindrop.io/v1/authentication)

# Make authorized calls

Build something great

Once you have received an **access_token**, include it in all API calls in [authorization header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Authorization) with value `Bearer access_token`

Copy

```
Authorization: Bearer ae261404-11r4-47c0-bce3-e18a423da828
```

[PreviousObtain access token](https://developer.raindrop.io/v1/authentication/token)[  
](https://developer.raindrop.io/v1/collections)

# Collections

### 

[](https://developer.raindrop.io/v1/collections#fields)

Fields

Field

Type

Description

_id

`Integer`

The id of the collection.

access

`Object`

access.level

`Integer`

1. read only access (equal to `public=true`)
    
2. collaborator with read only access
    
3. collaborator with write only access
    
4. owner
    

access.draggable

`Boolean`

Does it possible to change parent of this collection?

collaborators

`Object`

When this object is present, means that collections is shared. Content of this object is private and not very useful. All sharing API methods [described here](https://developer.raindrop.io/v1/collections/sharing)

color

`String`

Primary color of collection cover as `HEX`

count

`Integer`

Count of raindrops in collection

cover

`Array<String>`

Collection cover URL. This array always have one item due to legacy reasons

created

`String`

When collection is created

expanded

`Boolean`

Whether the collection’s sub-collections are expanded

lastUpdate

`String`

When collection is updated

parent

`Object`

parent.$id

`Integer`

The id of the parent collection. Not specified for root collections

public

`Boolean`

Collection and raindrops that it contains will be accessible without authentication by public link

sort

`Integer`

The order of collection (descending). Defines the position of the collection among all the collections with the same `parent.$id`

title

`String`

Name of the collection

user

`Object`

user.$id

`Integer`

Owner ID

view

`String`

View style of collection, can be:

- `list` (default)
    
- `simple`
    
- `grid`
    
- `masonry` Pinterest like grid
    

Our API response could contain **other fields**, not described above. It's **unsafe to use** them in your integration! They could be removed or renamed at any time.

### 

[](https://developer.raindrop.io/v1/collections#system-collections)

System collections

Every user have several system non-removable collections. They are not contained in any API responses.

_id

Description

**-1**

"**Unsorted**" collection

**-99**

"**Trash**" collection

[PreviousMake authorized calls](https://developer.raindrop.io/v1/authentication/calls)[  
](https://developer.raindrop.io/v1/collections/methods)

# Nested structure

### 

[](https://developer.raindrop.io/v1/collections/nested-structure#overview)

Overview

If you look into Raindrop UI you will notice a sidebar in left corner, where collections are located. Collections itself divided by groups. Groups useful to create separate sets of collections, for example "Home", "Work", etc.

![](https://developer.raindrop.io/~gitbook/image?url=https%3A%2F%2F3611960587-files.gitbook.io%2F%7E%2Ffiles%2Fv0%2Fb%2Fgitbook-legacy-files%2Fo%2Fassets%252F-M-GPP1TyNN8gNuijaj7%252F-M-odRbpHbUQpG6FIdE7%252F-M-oefnkLiSk6-lmT35A%252Fsidebar.png%3Falt%3Dmedia%26token%3De4070997-e45a-4310-a848-10995a597a6a&width=768&dpr=4&quality=100&sign=46681ac1&sv=2)

`Groups` array is a single place where user **root** collection list and order is persisted. Why just not to save order position inside collection item itself? Because collections can be shared and they group and order can vary from user to user.

So to fully recreate sidebar like in our app you need to make 3 separate API calls (sorry, will be improved in future API updates):

#### 

[](https://developer.raindrop.io/v1/collections/nested-structure#id-1.-get-user-object)

1. [Get user object](https://developer.raindrop.io/v1/user/authenticated#get-user)

It contains `groups` array with exact collection ID's. Typically this array looks like this:

Copy

```
{
  "groups": [
    {
      "title": "Home",
      "hidden": false,
      "sort": 0,
      "collections": [
        8364483,
        8364403,
        66
      ]
    },
    {
      "title": "Work",
      "hidden": false,
      "sort": 1,
      "collections": [
        8492393
      ]
    }
  ]
}
```

Collection ID's listed below is just first level of collections structure! To create full tree of nested collections you need to get child items separately.

To get name, count, icon and other info about collections, make those two separate calls:

#### 

[](https://developer.raindrop.io/v1/collections/nested-structure#id-2.-get-root-collections)

2. [Get root collections](https://developer.raindrop.io/v1/collections/methods#get-root-collections)

Sort order of root collections persisted in `groups[].collections` array

#### 

[](https://developer.raindrop.io/v1/collections/nested-structure#id-3.-get-child-collections)

3. [Get child collections](https://developer.raindrop.io/v1/collections/methods#get-child-collections)

Sort order of child collections persisted in collection itself in `sort` field

# Sharing

Collection can be shared with other users, which are then called collaborators, and this section describes the different commands that are related to sharing.

### 

[](https://developer.raindrop.io/v1/collections/sharing#collaborators)

Collaborators

Every user who shares at least one collection with another user, has a collaborators record in the API response. The record contains a restricted subset of user-specific fields.

Field

Description

_id

User ID of the collaborator

email

Email of the collaborator

Empty when authorized user have read-only access

email_MD5

MD5 hash of collaborator email. Useful for using with Gravatar for example

fullName

Full name of the collaborator

role

Access level:

`**member**` have write access and can invite more users

`**viewer**` read-only access

## 

[](https://developer.raindrop.io/v1/collections/sharing#share-collection)

Share collection

`POST` `https://api.raindrop.io/rest/v1/collection/{id}/sharing`

Share collection with another user(s). As result invitation(s) will be send to specified email(s) with link to join collection.

#### 

[](https://developer.raindrop.io/v1/collections/sharing#path-parameters)

Path Parameters

Name

Type

Description

id

number

Existing collection ID

#### 

[](https://developer.raindrop.io/v1/collections/sharing#request-body)

Request Body

Name

Type

Description

role

string

Access level. Possible values: `**member**` `**viewer**`

emails

array

The user email(s) with whom to share the project. Maximum 10

200

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-200)

400

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-400)

403

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-403)

Copy

```
{
    "result": true,
    "emails": [
        "some@user.com",
        "other@user.com"
    ]
}
```

## 

[](https://developer.raindrop.io/v1/collections/sharing#get-collaborators-list-of-collection)

Get collaborators list of collection

`GET` `https://api.raindrop.io/rest/v1/collection/{id}/sharing`

#### 

[](https://developer.raindrop.io/v1/collections/sharing#path-parameters-1)

Path Parameters

Name

Type

Description

id

number

Existing collection ID

200

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-200-1)

Copy

```
{
  "items": [
    {
      "_id": 373381,
      "email": "some@mail.com",
      "email_MD5": "e12bda18ca265d3f3e30d247adea2549",
      "fullName": "Jakie Future",
      "registered": "2019-08-18T17:01:43.664Z",
      "role": "viewer"
    }
  ],
  "result": true
}
```

## 

[](https://developer.raindrop.io/v1/collections/sharing#unshare-or-leave-collection)

Unshare or leave collection

`DELETE` `https://api.raindrop.io/rest/v1/collection/{id}/sharing`

There two possible results of calling this method, depends on who authenticated user is: - **Owner**: collection will be unshared and all collaborators will be removed - **Member or viewer**: authenticated user will be removed from collaborators list

#### 

[](https://developer.raindrop.io/v1/collections/sharing#path-parameters-2)

Path Parameters

Name

Type

Description

id

number

Existing collection ID

200

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-200-2)

Copy

```
{
    "result": true
}
```

## 

[](https://developer.raindrop.io/v1/collections/sharing#change-access-level-of-collaborator)

Change access level of collaborator

`PUT` `https://api.raindrop.io/rest/v1/collection/{id}/sharing/{userId}`

#### 

[](https://developer.raindrop.io/v1/collections/sharing#path-parameters-3)

Path Parameters

Name

Type

Description

userId

number

User ID of collaborator

id

number

Existing collection ID

#### 

[](https://developer.raindrop.io/v1/collections/sharing#request-body-1)

Request Body

Name

Type

Description

role

string

`**member**` or `**viewer**`

200

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-200-3)

Copy

```
{
    "result": true
}
```

## 

[](https://developer.raindrop.io/v1/collections/sharing#delete-a-collaborator)

Delete a collaborator

`DELETE` `https://api.raindrop.io/rest/v1/collection/{id}/sharing/{userId}`

Remove an user from shared collection

#### 

[](https://developer.raindrop.io/v1/collections/sharing#path-parameters-4)

Path Parameters

Name

Type

Description

userId

number

User ID of collaborator

id

number

Existing collection ID

200

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-200-4)

Copy

```
{
    "result": true
}
```

## 

[](https://developer.raindrop.io/v1/collections/sharing#accept-an-invitation)

Accept an invitation

`POST` `https://api.raindrop.io/rest/v1/collection/{id}/join`

Accept an invitation to join a shared collection

#### 

[](https://developer.raindrop.io/v1/collections/sharing#path-parameters-5)

Path Parameters

Name

Type

Description

id

number

Existing collection ID

#### 

[](https://developer.raindrop.io/v1/collections/sharing#request-body-2)

Request Body

Name

Type

Description

token

string

Secret token from email

200

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-200-5)

403

[](https://developer.raindrop.io/v1/collections/sharing#tab-id-403-1)

Copy

```
{
    "result": true,
    "role": "member"
}
```

# Covers/icons

In your app you could easily make icon/cover selector from more than 10 000 icons

![](https://developer.raindrop.io/~gitbook/image?url=https%3A%2F%2F3611960587-files.gitbook.io%2F%7E%2Ffiles%2Fv0%2Fb%2Fgitbook-legacy-files%2Fo%2Fassets%252F-M-GPP1TyNN8gNuijaj7%252F-M-of5es4601IU9HtzYf%252F-M-ogjIOcDvx33liprkE%252Ficon%2520finder.png%3Falt%3Dmedia%26token%3D4a945b4a-4fad-4671-bea9-43494e3e9136&width=768&dpr=4&quality=100&sign=fb709825&sv=2)

## 

[](https://developer.raindrop.io/v1/collections/covers-icons#search-for-cover)

Search for cover

`GET` `https://api.raindrop.io/rest/v1/collections/covers/{text}`

Search for specific cover (icon)

#### 

[](https://developer.raindrop.io/v1/collections/covers-icons#path-parameters)

Path Parameters

Name

Type

Description

text

string

For example "pokemon"

200

[](https://developer.raindrop.io/v1/collections/covers-icons#tab-id-200)

Copy

```
{
  "items": [
    {
      "title": "Icons8",
      "icons": [
        {
          "png": "https://rd-icons-icons8.gumlet.com/color/5x/mystic-pokemon.png?fill-color=transparent"
        }
      ]
    },
    {
      "title": "Iconfinder",
      "icons": [
        {
          "png": "https://cdn4.iconfinder.com/data/icons/pokemon-go/512/Pokemon_Go-01-128.png",
          "svg": "https://api.iconfinder.com/v2/icons/1320040/formats/svg/1760420/download"
        }
      ]
    }
  ],
  "result": true
}
```

## 

[](https://developer.raindrop.io/v1/collections/covers-icons#featured-covers)

Featured covers

`GET` `https://api.raindrop.io/rest/v1/collections/covers`

#### 

[](https://developer.raindrop.io/v1/collections/covers-icons#path-parameters-1)

Path Parameters

Name

Type

Description

string

200

[](https://developer.raindrop.io/v1/collections/covers-icons#tab-id-200-1)

Copy

```
{
  "items": [
    {
      "title": "Colors circle",
      "icons": [
        {
          "png": "https://up.raindrop.io/collection/templates/colors/ios1.png"
        }
      ]
    },
    {
      "title": "Hockey",
      "icons": [
        {
          "png": "https://up.raindrop.io/collection/templates/hockey-18/12i.png"
        }
      ]
    }
  ]
}
```

[  
](https://developer.raindrop.io/v1/collections/sharing)

# Raindrops

We call bookmarks (or items) as "raindrops"

### 

[](https://developer.raindrop.io/v1/raindrops#main-fields)

Main fields

Field

Type

Description

_id

`Integer`

Unique identifier

collection

`Object`

​

collection.$id

`Integer`

Collection that the raindrop resides in

cover

`String`

Raindrop cover URL

created

`String`

Creation date

domain

`String`

Hostname of a link. Files always have `raindrop.io` hostname

excerpt

`String`

Description; max length: 10000

note

`String`

Note; max length: 10000

lastUpdate

`String`

Update date

link

`String`

URL

media

`Array<Object>`

​Covers list in format: `[ {"link":"url"} ]`

tags

`Array<String>`

Tags list

title

`String`

Title; max length: 1000

type

`String`

`link` `article` `image` `video` `document` or `audio`

user

`Object`

​

user.$id

`Integer`

Raindrop owner

### 

[](https://developer.raindrop.io/v1/raindrops#other-fields)

Other fields

Field

Type

Description

broken

`Boolean`

Marked as broken (original `link` is not reachable anymore)

cache

`Object`

Permanent copy (cached version) details

cache.status

`String`

`ready` `retry` `failed` `invalid-origin` `invalid-timeout` or `invalid-size`

cache.size

`Integer`

Full size in bytes

cache.created

`String`

Date when copy is successfully made

creatorRef

`Object`

Sometime raindrop may belong to other user, not to the one who created it. For example when this raindrop is created in shared collection by other user. This object contains info about original author.

creatorRef._id

`Integer`

Original author (user ID) of a raindrop

creatorRef.fullName

`String`

Original author name of a raindrop

file

`Object`

This raindrop uploaded from desktop

[Supported file formats](https://help.raindrop.io/article/48-uploading-files)

file.name

`String`

File name

file.size

`Integer`

File size in bytes

file.type

`String`

Mime type

important

`Boolean`

Marked as "favorite"

highlights

`Array`

highlights[]._id

`String`

Unique id of highlight

highlights[].text

`String`

Text of highlight (required)

highlights[].color

`String`

Color of highlight. Default `yellow` Can be `blue`, `brown`, `cyan`, `gray`, `green`, `indigo`, `orange`, `pink`, `purple`, `red`, `teal`, `yellow`

highlights[].note

`String`

Optional note for highlight

highlights[].created

`String`

Creation date of highlight

reminder

`Object`

Specify this object to attach reminder

reminder.data

`Date`

YYYY-MM-DDTHH:mm:ss.sssZ

# Single raindrop

In this page you will find how to retrieve, create, update or delete single raindrop.

## 

[](https://developer.raindrop.io/v1/raindrops/single#get-raindrop)

Get raindrop

`GET` `https://api.raindrop.io/rest/v1/raindrop/{id}`

#### 

[](https://developer.raindrop.io/v1/raindrops/single#path-parameters)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

200

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-200)

Copy

## 

[](https://developer.raindrop.io/v1/raindrops/single#create-raindrop)

Create raindrop

`POST` `https://api.raindrop.io/rest/v1/raindrop`

Description and possible values of fields described in "Fields"

#### 

[](https://developer.raindrop.io/v1/raindrops/single#request-body)

Request Body

Name

Type

Description

pleaseParse

object

Specify empty object to automatically parse meta data (cover, description, html) in the background

created

string

lastUpdate

string

order

number

Specify sort order (ascending). For example if you want to move raindrop to the first place set this field to **0**

important

boolean

tags

array

media

array

cover

string

collection

object

type

string

excerpt

string

note

string

title

string

link*

string

highlights

array

reminder

object

200

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-200-1)

Copy

```
{
    "result": true,
    "item": {
        ...
    }
}
```

## 

[](https://developer.raindrop.io/v1/raindrops/single#update-raindrop)

Update raindrop

`PUT` `https://api.raindrop.io/rest/v1/raindrop/{id}`

Description and possible values of fields described in "Fields"

#### 

[](https://developer.raindrop.io/v1/raindrops/single#path-parameters-1)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

#### 

[](https://developer.raindrop.io/v1/raindrops/single#request-body-1)

Request Body

Name

Type

Description

created

string

lastUpdate

string

pleaseParse

object

Specify empty object to re-parse link meta data (cover, type, html) in the background

order

number

Specify sort order (ascending). For example if you want to move raindrop to the first place set this field to **0**

important

boolean

tags

array

media

array

cover

string

collection

object

type

string

excerpt

string

note

string

title

string

link

string

highlights

array

reminder

object

200

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-200-2)

Copy

```
{
    "result": true,
    "item": {
        ...
    }
}
```

## 

[](https://developer.raindrop.io/v1/raindrops/single#remove-raindrop)

Remove raindrop

`DELETE` `https://api.raindrop.io/rest/v1/raindrop/{id}`

When you remove raindrop it will be moved to user `Trash` collection. But if you try to remove raindrop from `Trash`, it will be removed permanently.

#### 

[](https://developer.raindrop.io/v1/raindrops/single#path-parameters-2)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

200

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-200-3)

Copy

```
{
    "result": true
}
```

## 

[](https://developer.raindrop.io/v1/raindrops/single#upload-file)

Upload file

`PUT` `https://api.raindrop.io/rest/v1/raindrop/file`

Make sure to send PUT request with [multipart/form-data](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/POST#example) body

#### 

[](https://developer.raindrop.io/v1/raindrops/single#headers)

Headers

Name

Type

Description

Content-Type*

string

multipart/form-data

#### 

[](https://developer.raindrop.io/v1/raindrops/single#request-body-2)

Request Body

Name

Type

Description

file*

object

File

collectionId

String

Collection Id

200

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-200-4)

400

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-400)

Copy

```
{
    "result": true,
    "item": {
        "title": "File name",
        "type": "image",
        "link": "https://up.raindrop.io/raindrop/111/file.jpeg",
        "domain": "raindrop.io",
        "file": {
            "name": "File name.jpeg",
            "size": 10000
        }
        ...
    }
}
```

## 

[](https://developer.raindrop.io/v1/raindrops/single#upload-cover)

Upload cover

`PUT` `https://api.raindrop.io/rest/v1/raindrop/{id}/cover`

PNG, GIF or JPEG

#### 

[](https://developer.raindrop.io/v1/raindrops/single#path-parameters-3)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

#### 

[](https://developer.raindrop.io/v1/raindrops/single#headers-1)

Headers

Name

Type

Description

Content-Type*

string

multipart/form-data

#### 

[](https://developer.raindrop.io/v1/raindrops/single#request-body-3)

Request Body

Name

Type

Description

cover*

object

File

200

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-200-5)

400

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-400-1)

Copy

```
{
    "result": true,
    "item": {
        "cover": "https://up.raindrop.io/raindrop/...",
        "media": [
            {
                "link": "https://up.raindrop.io/raindrop/..."
            }
        ]
        ...
    }
}
```

## 

[](https://developer.raindrop.io/v1/raindrops/single#get-permanent-copy)

Get permanent copy

`GET` `https://api.raindrop.io/rest/v1/raindrop/{id}/cache`

Links permanently saved with all content (only in PRO plan). Using this method you can navigate to this copy.

#### 

[](https://developer.raindrop.io/v1/raindrops/single#path-parameters-4)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

307

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-307)

Copy

```
Location: https://s3.aws...
```

## 

[](https://developer.raindrop.io/v1/raindrops/single#suggest-collection-and-tags-for-new-bookmark)

Suggest collection and tags for new bookmark

`POST` `https://api.raindrop.io/rest/v1/raindrop/suggest`

#### 

[](https://developer.raindrop.io/v1/raindrops/single#request-body-4)

Request Body

Name

Type

Description

link*

string

200

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-200-6)

Copy

```
{
    "result": true,
    "item": {
        "collections": [
            {
                "$id": 568368
            },
            {
                "$id": 8519567
            },
            {
                "$id": 1385626
            },
            {
                "$id": 8379661
            },
            {
                "$id": 20865985
            }
        ],
        "tags": [
            "fonts",
            "free",
            "engineering",
            "icons",
            "invalid_parser"
        ]
    }
}
```

## 

[](https://developer.raindrop.io/v1/raindrops/single#suggest-collection-and-tags-for-existing-bookmark)

Suggest collection and tags for existing bookmark

`GET` `https://api.raindrop.io/rest/v1/raindrop/{id}/suggest`

#### 

[](https://developer.raindrop.io/v1/raindrops/single#path-parameters-5)

Path Parameters

Name

Type

Description

*

String

Bookmark id

200

[](https://developer.raindrop.io/v1/raindrops/single#tab-id-200-7)

Copy

```
{
    "result": true,
    "item": {
        "collections": [
            {
                "$id": 568368
            },
            {
                "$id": 8519567
            },
            {
                "$id": 1385626
            },
            {
                "$id": 8379661
            },
            {
                "$id": 20865985
            }
        ],
        "tags": [
            "fonts",
            "free",
            "engineering",
            "icons",
            "invalid_parser"
        ]
    }
}
```

[  
](https://developer.raindrop.io/v1/raindrops)


# Multiple raindrops

In this page you will find how to retrieve, create, update or delete multiple raindrops at once.

### 

[](https://developer.raindrop.io/v1/raindrops/multiple#common-parameters)

Common parameters

To filter, sort or limit raindrops use one of the parameters described below. Check each method for exact list of supported parameters.

Parameter

Type

Description

collectionId

`Integer`

Path parameter that specify from which collection to get raindrops. Or specify one of system:

`0` to get all (except Trash)

`-1` to get from "Unsorted"

`-99` to get from "Trash"

Warning: update or remove methods not support `0` yet. Will be fixed in future.

search

`String`

As text, check all [examples here](https://help.raindrop.io/using-search#operators)

You can first test your searches in Raindrop app and if it works correctly, just copy content of search field and use it here

sort

`String`

Query parameter for sorting:

`-created` by date descending (default)

`created` by date ascending

`score` by relevancy (only applicable when search is specified)

`-sort` by order

`title` by title (ascending)

`-title` by title (descending)

`domain` by hostname (ascending)

`-domain` by hostname (descending)

page

`Integer`

Query parameter. 0, 1, 2, 3 ...

perpage

`Integer`

Query parameter. How many raindrops per page. 50 max

ids

`Array<Integer>`

You can specify exact raindrop ID's for batch update/remove methods

nested

`Boolean`

Also include bookmarks from nested collections (true/false)

## 

[](https://developer.raindrop.io/v1/raindrops/multiple#get-raindrops)

Get raindrops

`GET` `https://api.raindrop.io/rest/v1/raindrops/{collectionId}`

#### 

[](https://developer.raindrop.io/v1/raindrops/multiple#path-parameters)

Path Parameters

Name

Type

Description

collectionId*

number

Collection ID. Specify 0 to get all raindrops

#### 

[](https://developer.raindrop.io/v1/raindrops/multiple#query-parameters)

Query Parameters

Name

Type

Description

sort

string

perpage

number

page

number

search

string

nested

boolean

200

[](https://developer.raindrop.io/v1/raindrops/multiple#tab-id-200)

Copy

## 

[](https://developer.raindrop.io/v1/raindrops/multiple#create-many-raindrops)

Create many raindrops

`POST` `https://api.raindrop.io/rest/v1/raindrops`

#### 

[](https://developer.raindrop.io/v1/raindrops/multiple#request-body)

Request Body

Name

Type

Description

items*

array

Array of objects. Format of single object described in "Create single raindrop". Maximum 100 objects in array!

200

[](https://developer.raindrop.io/v1/raindrops/multiple#tab-id-200-1)

Copy

```
{
    "result": true,
    "items": [
        {
            ...
        }
    ]
}
```

## 

[](https://developer.raindrop.io/v1/raindrops/multiple#update-many-raindrops)

Update many raindrops

`PUT` `https://api.raindrop.io/rest/v1/raindrops/{collectionId}`

Specify optional `search` and/or `ids` parameters to limit raindrops that will be updated. Possible fields that could be updated are described in "Body Parameters"

#### 

[](https://developer.raindrop.io/v1/raindrops/multiple#path-parameters-1)

Path Parameters

Name

Type

Description

collectionId*

number

nested

boolean

#### 

[](https://developer.raindrop.io/v1/raindrops/multiple#request-body-1)

Request Body

Name

Type

Description

ids

array

important

boolean

TRUE - mark as "favorite" FALSE - unmark as "favorite"

tags

array

Will append specified tags to raindrops. Or will remove all tags from raindrops if `[]` (empty array) is specified

media

array

Will append specified media items to raindrops. Or will remove all media from raindrops if `[]` (empty array) is specified

cover

string

Set URL for cover. _Tip:_ specify `<screenshot>` to set screenshots for all raindrops

collection

object

Specify `{"$id": collectionId}` to move raindrops to other collection

200

[](https://developer.raindrop.io/v1/raindrops/multiple#tab-id-200-2)

Copy

## 

[](https://developer.raindrop.io/v1/raindrops/multiple#remove-many-raindrops)

Remove many raindrops

`DELETE` `https://api.raindrop.io/rest/v1/raindrops/{collectionId}`

Specify optional `search` and/or `ids` parameters to limit raindrops that will be moved to "**Trash**" When `:collectionId` is **-99**, raindrops will be permanently removed!

#### 

[](https://developer.raindrop.io/v1/raindrops/multiple#path-parameters-2)

Path Parameters

Name

Type

Description

collectionId*

number

nested

boolean

#### 

[](https://developer.raindrop.io/v1/raindrops/multiple#query-parameters-1)

Query Parameters

Name

Type

Description

search

string

#### 

[](https://developer.raindrop.io/v1/raindrops/multiple#request-body-2)

Request Body

Name

Type

Description

ids

array

200

[](https://developer.raindrop.io/v1/raindrops/multiple#tab-id-200-3)

Copy

```
{
    "result": true,
    "modified": 330
}
```

[  
](https://developer.raindrop.io/v1/raindrops/single)

# Highlights

Single `highlight` object:

Field

Type

Description

_id

`String`

Unique id of highlight

text

`String`

Text of highlight (required)

title

`String`

Title of bookmark

color

`String`

Color of highlight. Default `yellow` Can be `blue`, `brown`, `cyan`, `gray`, `green`, `indigo`, `orange`, `pink`, `purple`, `red`, `teal`, `yellow`

note

`String`

Optional note for highlight

created

`String`

Creation date of highlight

tags

`Array`

Tags list

link

`String`

Highlighted page URL

## 

[](https://developer.raindrop.io/v1/highlights#get-all-highlights)

Get all highlights

`GET` `https://api.raindrop.io/rest/v1/highlights`

#### 

[](https://developer.raindrop.io/v1/highlights#query-parameters)

Query Parameters

Name

Type

Description

page

Number

perpage

Number

How many highlights per page. 50 max. Default 25

200: OK

[](https://developer.raindrop.io/v1/highlights#tab-id-200-ok)

Copy

```
{
    "result": true,
    "items": [
        {
            "note": "Trully native macOS app",
            "color": "red",
            "text": "Orion is the new WebKit-based browser for Mac",
            "created": "2022-03-21T14:41:34.059Z",
            "tags": ["tag1", "tag2"],
            "_id": "62388e9e48b63606f41e44a6",
            "raindropRef": 123,
            "link": "https://apple.com",
            "title": "Orion Browser"
        },
        {
            "note": "",
            "color": "green",
            "text": "Built on WebKit, Orion gives you a fast, smooth and lightweight browsing experience",
            "created": "2022-03-21T15:13:21.128Z",
            "tags": ["tag1", "tag2"],
            "_id": "62389611058af151c840f667",
            "raindropRef": 123,
            "link": "https://apple.com",
            "title": "Apple"
        }
    ]
}
```

## 

[](https://developer.raindrop.io/v1/highlights#get-all-highlights-in-a-collection)

Get all highlights in a collection

`GET` `https://api.raindrop.io/rest/v1/highlights/{collectionId}`

#### 

[](https://developer.raindrop.io/v1/highlights#path-parameters)

Path Parameters

Name

Type

Description

collectionId*

Number

Collection ID

page

Number

perpage

Number

How many highlights per page. 50 max. Default 25

200: OK

[](https://developer.raindrop.io/v1/highlights#tab-id-200-ok-1)

Copy

```
{
    "result": true,
    "items": [
        {
            "note": "Trully native macOS app",
            "color": "red",
            "text": "Orion is the new WebKit-based browser for Mac",
            "created": "2022-03-21T14:41:34.059Z",
            "tags": ["tag1", "tag2"],
            "_id": "62388e9e48b63606f41e44a6",
            "raindropRef": 123,
            "link": "https://apple.com",
            "title": "Apple"
        },
        {
            "note": "",
            "color": "green",
            "text": "Built on WebKit, Orion gives you a fast, smooth and lightweight browsing experience",
            "created": "2022-03-21T15:13:21.128Z",
            "tags": ["tag1", "tag2"],
            "_id": "62389611058af151c840f667",
            "raindropRef": 123,
            "link": "https://apple.com",
            "title": "Apple"
        }
    ]
}
```

## 

[](https://developer.raindrop.io/v1/highlights#get-highlights-of-raindrop)

Get highlights of raindrop

`GET` `https://api.raindrop.io/rest/v1/raindrop/{id}`

#### 

[](https://developer.raindrop.io/v1/highlights#path-parameters-1)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

200

[](https://developer.raindrop.io/v1/highlights#tab-id-200)

Copy

```
{
    "result": true,
    "item": {
        "_id": 373777232,
        "highlights": [
            {
                "note": "Trully native macOS app",
                "color": "red",
                "text": "Orion is the new WebKit-based browser for Mac",
                "created": "2022-03-21T14:41:34.059Z",
                "lastUpdate": "2022-03-22T14:30:52.004Z",
                "_id": "62388e9e48b63606f41e44a6"
            },
            {
                "note": "",
                "color": "green",
                "text": "Built on WebKit, Orion gives you a fast, smooth and lightweight browsing experience",
                "created": "2022-03-21T15:13:21.128Z",
                "lastUpdate": "2022-03-22T09:15:18.751Z",
                "_id": "62389611058af151c840f667"
            }
        ]
    }
}
```

## 

[](https://developer.raindrop.io/v1/highlights#add-highlight)

Add highlight

`PUT` `https://api.raindrop.io/rest/v1/raindrop/{id}`

Just specify a `highlights` array in body with `object` for each highlight

**Fore example:**

`{"highlights": [ { "text": "Some quote", "color": "red", "note": "Some note" } ] }`

#### 

[](https://developer.raindrop.io/v1/highlights#path-parameters-2)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

#### 

[](https://developer.raindrop.io/v1/highlights#request-body)

Request Body

Name

Type

Description

highlights*

array

highlights[].text*

String

highlights[].note

String

highlights[].color

String

200

[](https://developer.raindrop.io/v1/highlights#tab-id-200-1)

Copy

```
{
    "result": true,
    "item": {
        "_id": 373777232,
        "highlights": [
            {
                "note": "Trully native macOS app",
                "color": "red",
                "text": "Orion is the new WebKit-based browser for Mac",
                "created": "2022-03-21T14:41:34.059Z",
                "lastUpdate": "2022-03-22T14:30:52.004Z",
                "_id": "62388e9e48b63606f41e44a6"
            },
            {
                "note": "",
                "color": "green",
                "text": "Built on WebKit, Orion gives you a fast, smooth and lightweight browsing experience",
                "created": "2022-03-21T15:13:21.128Z",
                "lastUpdate": "2022-03-22T09:15:18.751Z",
                "_id": "62389611058af151c840f667"
            }
        ]
    }
}
```

## 

[](https://developer.raindrop.io/v1/highlights#update-highlight)

Update highlight

`PUT` `https://api.raindrop.io/rest/v1/raindrop/{id}`

Just specify a `highlights` array in body with `object` containing particular `_id` of highlight you want to update and all other fields you want to change.

**Fore example:**

`{"highlights": [ { "_id": "62388e9e48b63606f41e44a6", "note": "New note" } ] }`

#### 

[](https://developer.raindrop.io/v1/highlights#path-parameters-3)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

#### 

[](https://developer.raindrop.io/v1/highlights#request-body-1)

Request Body

Name

Type

Description

highlights*

array

highlights[]._id*

String

Particular highlight _id you want to remove

highlights[].text

String

Should be empty string

highlights[].note

String

highlights[].color

String

200

[](https://developer.raindrop.io/v1/highlights#tab-id-200-2)

Copy

```
{
    "result": true,
    "item": {
        "_id": 373777232,
        "highlights": [
            {
                "note": "Trully native macOS app",
                "color": "red",
                "text": "Orion is the new WebKit-based browser for Mac",
                "created": "2022-03-21T14:41:34.059Z",
                "lastUpdate": "2022-03-22T14:30:52.004Z",
                "_id": "62388e9e48b63606f41e44a6"
            },
            {
                "note": "",
                "color": "green",
                "text": "Built on WebKit, Orion gives you a fast, smooth and lightweight browsing experience",
                "created": "2022-03-21T15:13:21.128Z",
                "lastUpdate": "2022-03-22T09:15:18.751Z",
                "_id": "62389611058af151c840f667"
            }
        ]    }}
```

## 

[](https://developer.raindrop.io/v1/highlights#remove-highlight)

Remove highlight

`PUT` `https://api.raindrop.io/rest/v1/raindrop/{id}`

Just specify a `highlights` array in body with `object` containing particular `_id` of highlight you want to remove and empty string for `text` field.

**Fore example:**

`{"highlights": [ { "_id": "62388e9e48b63606f41e44a6", "text": "" } ] }`

#### 

[](https://developer.raindrop.io/v1/highlights#path-parameters-4)

Path Parameters

Name

Type

Description

id*

number

Existing raindrop ID

#### 

[](https://developer.raindrop.io/v1/highlights#request-body-2)

Request Body

Name

Type

Description

highlights*

array

highlights[]._id*

String

Particular highlight _id you want to remove

highlights[].text*

String

Should be empty string

200

[](https://developer.raindrop.io/v1/highlights#tab-id-200-3)

Copy

```
{
    "result": true,
    "item": {
        "_id": 373777232,
        "highlights": [
            {
                "note": "Trully native macOS app",
                "color": "red",
                "text": "Orion is the new WebKit-based browser for Mac",
                "created": "2022-03-21T14:41:34.059Z",
                "lastUpdate": "2022-03-22T14:30:52.004Z",
                "_id": "62388e9e48b63606f41e44a6"
            },
            {
                "note": "",
                "color": "green",
                "text": "Built on WebKit, Orion gives you a fast, smooth and lightweight browsing experience",
                "created": "2022-03-21T15:13:21.128Z",
                "lastUpdate": "2022-03-22T09:15:18.751Z",
                "_id": "62389611058af151c840f667"
            }
        ]
    }}
```

[  
](https://developer.raindrop.io/v1/raindrops/multiple)

# User

### 

[](https://developer.raindrop.io/v1/user#main-fields)

Main fields

Field

Publicly visible

Type

Description

_id

**Yes**

`Integer`

Unique user ID

config

No

`Object`

More details in "Config fields"

email

No

`String`

Only visible for you

email_MD5

**Yes**

`String`

MD5 hash of email. Useful for using with Gravatar for example

files.used

No

`Integer`

How much space used for files this month

files.size

No

`Integer`

Total space for file uploads

files.lastCheckPoint

No

`String`

When space for file uploads is reseted last time

fullName

**Yes**

`String`

Full name, max 1000 chars

groups

No

`Array<Object>`

More details below in "Groups"

password

No

`Boolean`

Does user have a password

pro

**Yes**

`Boolean`

PRO subscription

proExpire

No

`String`

When PRO subscription will expire

registered

No

`String`

Registration date

### 

[](https://developer.raindrop.io/v1/user#config-fields)

Config fields

Field

Publicly visible

Type

Description

config.broken_level

No

`String`

Broken links finder configuration, possible values:

`basic` `default` `strict` or `off`

config.font_color

No

`String`

Bookmark preview style: `sunset` `night` or empty

config.font_size

No

`Integer`

Bookmark preview font size: from 0 to 9

config.lang

No

`String`

UI language in 2 char code

config.last_collection

No

`Integer`

Last viewed collection ID

config.raindrops_sort

No

`String`

Default bookmark sort:

`title` `-title` `-sort` `domain` `-domain` `+lastUpdate` or `-lastUpdate`

config.raindrops_view

No

`String`

Default bookmark view:

`grid` `list` `simple` or `masonry`

### 

[](https://developer.raindrop.io/v1/user#single-group-detail)

Groups object fields

Field

Type

Description

title

`String`

Name of group

hidden

`Boolean`

Does group is collapsed

sort

`Integer`

Ascending order position

collections

`Array<Integer>`

Collection ID's in order

### 

[](https://developer.raindrop.io/v1/user#other-fields)

Other fields

Field

Publicly visible

Type

Description

facebook.enabled

No

`Boolean`

Does Facebook account is linked

twitter.enabled

No

`Boolean`

Does Twitter account is linked

vkontakte.enabled

No

`Boolean`

Does Vkontakte account is linked

google.enabled

No

`Boolean`

Does Google account is linked

dropbox.enabled

No

`Boolean`

Does Dropbox backup is enabled

gdrive.enabled

No

`Boolean`

Does Google Drive backup is enabled

# Authenticated user

## 

[](https://developer.raindrop.io/v1/user/authenticated#get-user)

Get user

`GET` `https://api.raindrop.io/rest/v1/user`

Get currently authenticated user details

200

[](https://developer.raindrop.io/v1/user/authenticated#tab-id-200)

401

[](https://developer.raindrop.io/v1/user/authenticated#tab-id-401)

Copy

```
{
    "result": true,
    "user": {
      "_id": 32,
      "config": {
        "broken_level": "strict",
        "font_color": "",
        "font_size": 0,
        "lang": "ru_RU",
        "last_collection": 8492393,
        "raindrops_sort": "-lastUpdate",
        "raindrops_view": "list"
      },
      "dropbox": {
        "enabled": true
      },
      "email": "some@email.com",
      "email_MD5": "13a0a20681d8781912e5314150694bf7",
      "files": {
        "used": 6766094,
        "size": 10000000000,
        "lastCheckPoint": "2020-01-26T23:53:19.676Z"
      },
      "fullName": "Mussabekov Rustem",
      "gdrive": {
        "enabled": true
      },
      "groups": [
        {
          "title": "My Collections",
          "hidden": false,
          "sort": 0,
          "collections": [
            8364483,
            8364403,
            66
          ]
        }
      ],
      "password": true,
      "pro": true,
      "proExpire": "2028-09-27T22:00:00.000Z",
      "registered": "2014-09-30T07:51:15.406Z"
  }
}
```

## 

[](https://developer.raindrop.io/v1/user/authenticated#get-user-by-name)

Get user by name

`GET` `https://api.raindrop.io/rest/v1/user/{name}`

Get's publicly available user details

#### 

[](https://developer.raindrop.io/v1/user/authenticated#path-parameters)

Path Parameters

Name

Type

Description

name*

number

Username

200

[](https://developer.raindrop.io/v1/user/authenticated#tab-id-200-1)

404

[](https://developer.raindrop.io/v1/user/authenticated#tab-id-404)

Copy

```
{
  "result": true,
  "user": {
    "_id": 32,
    "email_MD5": "13a0a20681d8781912e5314150694bf7",
    "fullName": "Mussabekov Rustem",
    "pro": true,
    "registered": "2014-09-30T07:51:15.406Z"
  }
}
```

## 

[](https://developer.raindrop.io/v1/user/authenticated#update-user)

Update user

`PUT` `https://api.raindrop.io/rest/v1/user`

To change email, config, password, etc... you can do it from single endpoint

#### 

[](https://developer.raindrop.io/v1/user/authenticated#request-body)

Request Body

Name

Type

Description

groups

array

config

object

newpassword

string

oldpassword

string

fullName

string

email

string

200

[](https://developer.raindrop.io/v1/user/authenticated#tab-id-200-2)

400

[](https://developer.raindrop.io/v1/user/authenticated#tab-id-400)

Copy

```
{
    "result": true,
    "user": {
        ...
    }
}
```

## 

[](https://developer.raindrop.io/v1/user/authenticated#connect-social-network-account)

Connect social network account

`GET` `https://api.raindrop.io/rest/v1/user/connect/{provider}`

Connect social network account as sign in authentication option

#### 

[](https://developer.raindrop.io/v1/user/authenticated#path-parameters-1)

Path Parameters

Name

Type

Description

provider

string

`facebook` `google` `twitter` `vkontakte` `dropbox` or `gdrive`

307

[](https://developer.raindrop.io/v1/user/authenticated#tab-id-307)

Copy

```
Location: https://some.com/...
```

## 

[](https://developer.raindrop.io/v1/user/authenticated#disconnect-social-network-account)

Disconnect social network account

`GET` `https://api.raindrop.io/rest/v1/user/connect/{provider}/revoke`

Disconnect social network account from available authentication options

#### 

[](https://developer.raindrop.io/v1/user/authenticated#path-parameters-2)

Path Parameters

Name

Type

Description

provider

string

`facebook` `google` `twitter` `vkontakte` `dropbox` or `gdrive`

200

[](https://developer.raindrop.io/v1/user/authenticated#tab-id-200-3)

Copy

[  
](https://developer.raindrop.io/v1/user)

# Tags

## 

[](https://developer.raindrop.io/v1/tags#get-tags)

Get tags

`GET` `https://api.raindrop.io/rest/v1/tags/{collectionId}`

#### 

[](https://developer.raindrop.io/v1/tags#path-parameters)

Path Parameters

Name

Type

Description

collectionId

number

Optional collection ID, when not specified all tags from all collections will be retrieved

200

[](https://developer.raindrop.io/v1/tags#tab-id-200)

Copy

```
{
    "result": true,
    "items": [
        {
            "_id": "api",
            "count": 100
        }
    ]
}
```

## 

[](https://developer.raindrop.io/v1/tags#rename-tag)

Rename tag

`PUT` `https://api.raindrop.io/rest/v1/tags/{collectionId}`

#### 

[](https://developer.raindrop.io/v1/tags#path-parameters-1)

Path Parameters

Name

Type

Description

collectionId

number

It's possible to restrict rename action to just one collection. It's optional

#### 

[](https://developer.raindrop.io/v1/tags#request-body)

Request Body

Name

Type

Description

replace

string

New name

tags

array

Specify **array** with **only one** string (name of a tag)

200

[](https://developer.raindrop.io/v1/tags#tab-id-200-1)

Copy

```
{
    "result": true
}
```

## 

[](https://developer.raindrop.io/v1/tags#merge-tags)

Merge tags

`PUT` `https://api.raindrop.io/rest/v1/tags/{collectionId}`

Basically this action rename bunch of `tags` to new name (`replace` field)

#### 

[](https://developer.raindrop.io/v1/tags#path-parameters-2)

Path Parameters

Name

Type

Description

collectionId

string

It's possible to restrict merge action to just one collection. It's optional

#### 

[](https://developer.raindrop.io/v1/tags#request-body-1)

Request Body

Name

Type

Description

replace

string

New name

tags

array

List of tags

200

[](https://developer.raindrop.io/v1/tags#tab-id-200-2)

Copy

```
{
    "result": true
}
```

## 

[](https://developer.raindrop.io/v1/tags#remove-tag-s)

Remove tag(s)

`DELETE` `https://api.raindrop.io/rest/v1/tags/{collectionId}`

#### 

[](https://developer.raindrop.io/v1/tags#path-parameters-3)

Path Parameters

Name

Type

Description

collectionId

string

It's possible to restrict remove action to just one collection. It's optional

#### 

[](https://developer.raindrop.io/v1/tags#request-body-2)

Request Body

Name

Type

Description

tags

array

List of tags

200

[](https://developer.raindrop.io/v1/tags#tab-id-200-3)

Copy

```
{
    "result": true
}
```

[  
](https://developer.raindrop.io/v1/user/authenticated)

# Filters

To help users easily find their content you can suggest context aware filters like we have in Raindrop.io app

![](https://developer.raindrop.io/~gitbook/image?url=https%3A%2F%2F3611960587-files.gitbook.io%2F%7E%2Ffiles%2Fv0%2Fb%2Fgitbook-legacy-files%2Fo%2Fassets%252F-M-GPP1TyNN8gNuijaj7%252F-M-oej2Q4_QeQb3lfFaV%252F-M-of2jvit9BqVisVU9y%252Ffilters.png%3Falt%3Dmedia%26token%3Dd1992f10-6dc3-401c-9332-81e69fc876ac&width=768&dpr=4&quality=100&sign=2ca74481&sv=2)

Filters right above search field

## 

[](https://developer.raindrop.io/v1/filters#fields)

Fields

Field

Type

Description

broken

`Object`

broken.count

`Integer`

Broken links count

duplicates

`Object`

duplicates.count

`Integer`

Duplicate links count

important

`Object`

important.count

`Integer`

Count of raindrops that marked as "favorite"

notag

`Object`

notag.count

`Integer`

Count of raindrops without any tag

tags

`Array<Object>`

List of tags in format `{"_id": "tag name", "count": 1}`

types

`Array<Object>`

List of types in format `{"_id": "type", "count": 1}`

## 

[](https://developer.raindrop.io/v1/filters#get-filters)

Get filters

`GET` `https://api.raindrop.io/rest/v1/filters/{collectionId}`

#### 

[](https://developer.raindrop.io/v1/filters#path-parameters)

Path Parameters

Name

Type

Description

collectionId

string

Collection ID. `0` for all

#### 

[](https://developer.raindrop.io/v1/filters#query-parameters)

Query Parameters

Name

Type

Description

tagsSort

string

Sort tags by: `**-count**` by count, default `**_id**` by name

search

string

Check "raindrops" documentation for more details

200

[](https://developer.raindrop.io/v1/filters#tab-id-200)

Copy

```
{
  "result": true,
  "broken": {
    "count": 31
  },
  "duplicates": {
    "count": 7
  },
  "important": {
    "count": 59
  },
  "notag": {
    "count": 1366
  },
  "tags": [
    {
      "_id": "performanc",
      "count": 19
    },
    {
      "_id": "guides",
      "count": 9
    }
  ],
  "types": [
    {
      "_id": "article",
      "count": 313
    },
    {
      "_id": "image",
      "count": 143
    },
    {
      "_id": "video",
      "count": 26
    },
    {
      "_id": "document",
      "count": 7
    }
  ]
}
```

[  
](https://developer.raindrop.io/v1/tags)

# Import

Handy methods to implement import functionality

## 

[](https://developer.raindrop.io/v1/import#parse-url)

Parse URL

`GET` `https://api.raindrop.io/rest/v1/import/url/parse`

Parse and extract useful info from any URL

#### 

[](https://developer.raindrop.io/v1/import#query-parameters)

Query Parameters

Name

Type

Description

url

string

URL

200

[](https://developer.raindrop.io/v1/import#tab-id-200)

Copy

```
//Success
{
  "item": {
    "title": "Яндекс",
    "excerpt": "Найдётся всё",
    "media": [
      {
        "type": "image",
        "link": "http://yastatic.net/s3/home/logos/share/share-logo_ru.png"
      }
    ],
    "type": "link",
    "meta": {
      "possibleArticle": false,
      "canonical": "https://ya.ru",
      "site": "Яндекс",
      "tags": []
    }
  },
  "result": true
}

//Invalid URL
{
  "error": "not_found",
  "errorMessage": "invalid_url",
  "item": {
    "title": "Fdfdfdf",
    "excerpt": "",
    "media": [
      {
        "link": "<screenshot>"
      }
    ],
    "type": "link",
    "parser": "local",
    "meta": {
      "possibleArticle": false,
      "tags": []
    }
  },
  "result": true
}

//Not found
{
  "error": "not_found",
  "errorMessage": "url_status_404",
  "item": {
    "title": "Some",
    "excerpt": "",
    "media": [
      {
        "link": "<screenshot>"
      }
    ],
    "type": "link",
    "parser": "local",
    "meta": {
      "possibleArticle": false,
      "tags": []
    }
  },
  "result": true
}
```

## 

[](https://developer.raindrop.io/v1/import#check-url-s-existence)

Check URL(s) existence

`POST` `https://api.raindrop.io/rest/v1/import/url/exists`

Does specified URL's are already saved?

#### 

[](https://developer.raindrop.io/v1/import#request-body)

Request Body

Name

Type

Description

urls

array

URL's

200 ids array contains ID of existing bookmarks

[](https://developer.raindrop.io/v1/import#tab-id-200-ids-array-contains-id-of-existing-bookmarks)

Copy

```
//Found
{
    "result": true,
    "ids": [
        3322,
        12323
    ]
}

//Not found
{
    "result": false,
    "ids": []
}
```

## 

[](https://developer.raindrop.io/v1/import#parse-html-import-file)

Parse HTML import file

`POST` `https://api.raindrop.io/rest/v1/import/file`

Convert HTML bookmark file to JSON. Support Nestcape, Pocket and Instapaper file formats

#### 

[](https://developer.raindrop.io/v1/import#headers)

Headers

Name

Type

Description

Content-Type

string

multipart/form-data

#### 

[](https://developer.raindrop.io/v1/import#request-body-1)

Request Body

Name

Type

Description

import

string

File

200

[](https://developer.raindrop.io/v1/import#tab-id-200-1)

Copy

```
{
  "result": true,
  "items": [
    {
      "title": "Web",
      "folders": [
        {
          "title": "Default",
          "folders": [],
          "bookmarks": [
            {
              "link": "https://aaa.com/a",
              "title": "Name 1",
              "lastUpdate": "2016-09-13T11:17:09.000Z",
              "tags": ["tag"],
              "excerpt": ""
            }
          ]
        }
      ],
      "bookmarks": [
        {
          "link": "https://bbb.com/b",
          "title": "Name 2",
          "lastUpdate": "2016-09-13T11:17:09.000Z",
          "tags": ["tag"],
          "excerpt": ""
        }
      ]
    },
    {
      "title": "Home",
      "folders": [
        {
          "title": "Inspiration",
          "folders": [],
          "bookmarks": [
            {
              "link": "https://ccc.com/c",
              "title": "Name 3",
              "lastUpdate": "2016-09-13T11:17:09.000Z",
              "tags": ["tag"],
              "excerpt": ""
            }
          ]
        }
      ],
      "bookmarks": []
    }
  ]
}
```

[  
](https://developer.raindrop.io/v1/filters)

# Export

Export all raindrops in specific format

## 

[](https://developer.raindrop.io/v1/export#export-in-format)

Export in format

`GET` `https://api.raindrop.io/rest/v1/raindrops/{collectionId}/export.{format}`

**Path Parameters**

Name

Type

Description

`collectionId`*

number

Collection ID. Specify `0` to get all raindrops

`format`*

string

`csv`, `html` or `zip`

**Query Parameters**

Name

Type

Description

`sort`

string

Check [https://developer.raindrop.io/v1/raindrops/multiple](https://developer.raindrop.io/v1/raindrops/multiple)

`search`

string

Check [https://developer.raindrop.io/v1/raindrops/multiple](https://developer.raindrop.io/v1/raindrops/multiple)

[  
](https://developer.raindrop.io/v1/import)

# Backups

## 

[](https://developer.raindrop.io/v1/backups#get-all)

Get all

`GET` `https://api.raindrop.io/rest/v1/backups`

Useful to get backup ID's that can be used in `/backup/{ID}.{format}` endpoint.

Sorted by date (new first)

200

[](https://developer.raindrop.io/v1/backups#tab-id-200)

Copy

```
{
    "result": true,
    "items": [
        {
            "_id": "659d42a35ffbb2eb5ae1cb86",
            "created": "2024-01-09T12:57:07.630Z"
        }
    ]
}
```

## 

[](https://developer.raindrop.io/v1/backups#download-file)

Download file

`GET` `https://api.raindrop.io/rest/v1/backup/{ID}.{format}`

For example:

`https://api.raindrop.io/rest/v1/backup/659d42a35ffbb2eb5ae1cb86.csv`

#### 

[](https://developer.raindrop.io/v1/backups#path-parameters)

Path Parameters

Name

Type

Description

ID*

String

Backup ID

format*

String

File format: `html` or `csv`

## 

[](https://developer.raindrop.io/v1/backups#generate-new)

Generate new

`GET` `https://api.raindrop.io/rest/v1/backup`

Useful to create a brand new backup. This requires some time.

New backup will appear in the list of `/backups` endpoint

200

[](https://developer.raindrop.io/v1/backups#tab-id-200-1)

Copy

```
We will send you email with html export file when it be ready! Time depends on bookmarks count and queue.
```

[  
](https://developer.raindrop.io/v1/export)