# Messaging-Board
Messaging Board with a twist :)
<br>

### Overview
In this project I plan on implimenting a primitive web server for a messaging board in **asm** with my own communication protocol
<br>

### How to setup
If you want to try it out yourself you should just be able to run the **_.exe_** on any linux machine

### Compile it yourself
You can compile it yourself on a linux machine using
```
as -o ./main/main.o ./main/main.asm && ld -o ./main/main.exe ./main/main.o
```

### Use
To actually interact with the program, I'd recommend using ```ss -tln``` to find the port it was assigned and then using ```nc localhost some_port``` to connect to the server
<br><br>
Some examples for how you can interact with the web server can be found below
```
sJoey574;abcd                                # signup a user with the name Joey574 and the password abcd
lJoey574;abcd                                # login as the user with the name Joey574 and the password abcd
rauth_key                                    # read the public posts
wauth_keyToday, I managed to touch grass     # write a post
mauth_keyKian;Yo, how's it going?            # send a message to the user 'Kian'
iauth_key                                    # check your inbox for messages sent to you
```
You can also use ```nc localhost << EOF``` to write out multiple lines of text
<br>

## Web Server
The web server will have 6 different actions a user can perform:
* **Login**
* **Signup**
* **Read**
* **Post**
* **Inbox**
* **Message**

Immediately some people might be wondering how a database will be implemented for loging in, signing up, storing messages, etc. For this I plan to use the ever sophisticated *filesystem*, stored in mostly plaintext, as such I don't recommend using this for any top secret communications ;)
<br>

### Login
**NOTE:** Both **_username_** and **_password_** have a max size of **64 bytes** <br>
**READS:** Reads data from **_users.txt_** <br>
**RETURNS:** On success a 64 byte auth key, else some error info
<br><br>
The login method does not expect any auth key, however, it expects both a username and a password to be in the data section, in the format
```
example_user;example_password
```
The login method will then look through the **_users.txt_** file and if a matching username is found it will xor the password, padded out to 64 bytes, with some key and check if they match, if so returnning an auth key. The auth key is computed by taking the password ciphertext, and xor-ing it with the username padded out to 64 bytes
<br><br>
Padding will be done by simply adding 0x00 to the plaintext until it reaches the proper size, in the case of the password, this has the effect of making the xor-ed password the key itself for any character that's not given, definitely not best practice, but I wanted to do something that wasn't just storing plaintext, and AES seemed a bit too ambitious for a first project 
<br>

### Signup
**NOTE:** Both **_username_** and **_password_** have a max size of **64 bytes** <br>
**MODIFIES:** Given user doesn't already exist, user will be added to **_users.txt_** <br>
**READS:** Reads data from **_users.txt_** <br>
**RETURNS:** On success, a 64 byte auth key, else some error info
<br><br>
The **signup** method, like the **login** method, doesn't take an auth key, instead taking in a username and a password in the format
```
example_user;example_password    # same format as the login method
```
After parsing both the *username* and *password*, the method will search through the **_users.txt_** file to see if any user with the same name exists, if not, the username and password are appended to the file, the plaintext password will be xor-ed with the *auth_key* before being written to the file
<br><br>
Both *username* and *password* will be stored as 64 bytes regardless of what the user actually inputs, 0x00 will be appended to the both, until they each reach the proper length
<br><br>
Like the **login** method, an auth key will be returned on success, and is calculated in the same way

### Read
**READS:** Reads data from **_posts.txt_** and **_users.txt_**<br>
**RETURNS:** On success, posts from other users, else some error info
<br><br>
The read method expects a 64 byte auth key to be passed immediately after the action byte, from there, it will read through **_userstxt_** computing the auth key for each user and checking for a match, if a match is found it will then read data from **_posts.txt_** and return it, posts are stored as plaintext in the form
```
example_user: woah this is an example post!
```
No other data is expected to be in the request, any subsequent data will be ignored
<br>

### Post
**MODIFIES:** Modofies data from **_posts.txt_** <br>
**READS::** Reads data from **_users.txt_** <br>
**RETURNS:** On success, success info, else some error info
<br><br>
The post method expects a 64 byte auth key to be passed immediately after the action byte, like the read method (or for that matter any of the remaining functions) it will search through **_users.txt_** to confirm a matching auth key exists, the method expects any data past this point to be a part of the actual post, an example query might look like the following
```
pauth_keywoah this is an example post!
```
Once the post is parsed it will be written to the **_posts.txt_** file and a success message will be written back to the user, also important to note you can write multiple lines using ```nc localhost some_port << EOF ```
<br>

### Inbox
**READS:** Reads data from **_inbox/some_user.txt_** and **_users.txt_** <br>
**RETURNS:** On success, all messages sent to user, else some error info
<br><br>
Inbox expects a 64 byte auth key to be passed, if the auth key is valid it will then return their inbox file, if one exists, messages you recieve are stored in the same format as the **_posts.txt_** file

### Message
**MODIFIES:** Given *other_user* exists, modifies data from **_inbox/other_user.txt_** <br>
**READS:** Reads data from **_users.txt_** <br>
**RETURNS:** On success, success info, else some error info
<br><br>
Message expects a 64 byte auth key, a target user, and some message data to be passed in the form
```
mauth_keytarget_user;some_message
```
If the user is successfully authenticated, and *target_user* is actually a user in **_users.txt_**, *some_message* will be added to their inbox file, if it exists, otherwise it will be created.

## Communication Protocol
For how I want to communicate between user and web server, I decided it would be simpler, and more fun, to design my own basic protocol, as http is pretty lame anyways. 
<br><br>
The structure of the data is pretty simple, as we only have 3 sections we need to acount for
* **Action**
* **Authentication**
* **Data**

### Action
The action is encoded with 1 byte, with 6 different letters coresponding to the 6 supported actions of the web server
* **Login -> l**
* **Signup -> s**
* **Read -> r**
* **Post -> p**
* **Msg -> m**
* **Inbox -> i**

### Authentication
The auth is an optional 64 bytes of data, expected for any action that isn't **login** or **signup** 
<br><br>
You can find more info on how the authenticaiton token is computed in the **_login_** and **_signup_** sections, it's incredibly basic and I **DO NOT** recommend using it for anything serious
<br>

### Data
The next part to the protocol is the data section, this can be some arbitrary length, although since I'm reading into a buffer it will likely have a max length in the ballpark of **2kb** or so **_(actual size TBD)_**. 
<br><br>
**NOTE:** Depending on how the user is interacting with the web server, certain data will be expected to be in this section, **;** delimited, in some order, what kind of data and in what order is discussed in the **_Web Server_** section
