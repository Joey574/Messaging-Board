# Messaging-Board
Messaging Board with a twist ;)
<br>

### Overview
In this project I plan on implimenting a primitive web server for a messaging board in **asm** with my own communication protocol
<br>

### Set-up
If you want to try it out yourself you should just be able to run the **_.exe_** on any linux machine
<br><br>
To actually interact with the program, I'd recommend using
```
ss -tln
```
to find the port it was assigned and then using
```
nc localhost some_port
```
to write out your message
<br><br>

## Web Server
The web server will have 6 different actions a user can perform:
* **Login**
* **Signup**
* **Read**
* **Post**
* **Inbox**
* **Msg**

Immediately some people might be wondering how a database will be implemented for loging in, signing up, storing messages, etc. For this I plan to use the ever sophisticated *filesystem*, stored in mostly plaintext, as such I don't recommend using this for any top secret communications ;)
<br>

### Login
**NOTE:** Both **_username_** and **_password_** have a max size of **64 bytes** <br>
**READS:** Reads data from **_user.txt_** <br>
**RETURNS:** On success a 64 byte auth key, else some error info
<br><br>
The login method does not expect any auth key, however, it expects both a ussername and a password to be in the data section, in the format

```
example_user;example_password
```

The login method will then look through the **_user.txt_** file and if a matching username is found it will xor the password, padded out to 64 bytes, with some key and check if they match, if so returnning an auth key. The auth key is computed by taking the password ciphertext, and xor-ing it with the username padded out to 64 bytes.
<br><br>
Padding will be done by simply repeating the password out until it is 64 bytes long. **This is terrible.** It introduces some rather funny behavior such that
<br>
**a**
<br>
and
<br>
**aa**
<br>
and for that matter any repeated pattern will all result in the same ciphertext. *Feature, not a bug* ;)
```
This is a terrible way to secure anything DO NOT take notes from this
```
<br>

### Signup
**NOTE:** Both **_username_** and **_password_** have a max size of **64 bytes** <br>
**MODIFIES:** Given user doesn't already exist, user will be added to **_user.txt_** <br>
**RETURNS:** On success, a 64 byte auth key, else some error info
<br><br>


### Read
**READS:** Reads data from **_posts.txt_** <br>
**RETURNS:** On success, posts from other users, else some error info
<br><br>

### Post
**MODIFIES:** Modofies data from **_posts.txt_** <br>
**RETURNS:** On success, success info, else some error info
<br><br>

### Inbox
**READS:** Reads data from **_inbox/some_user.txt_** <br>
**RETURNS:** On success, all messages sent to user, else some error info
<br><br>

### Msg
**MODIFIES:** Given *other_user* exists, modifies data from **_inbox/other_user.txt_** <br>
**RETURNS:** On success, success info, else some error info
<br><br>

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
The auth key will be computed by taking the stored password, *(password plaintext xored with some const key)* and xor that with the username, if the username is not 64 bytes, it will be repeated out until it is the proper size
```
Again, this is not secure, do not take notes from this and be aware it is an awful attempt to secure anything
```
That being said, I wanted to do something that wasn't just storing plaintext, and I've been learning a little about cryptography as of late, so why the hell not
<br>

### Data
The next part to the protocol is the data section, this can be some arbitrary length, although since I'm reading into a buffer it will likely have a max length in the ballpark of **2kb** or so **_(actual size TBD)_**. 
<br><br>
**NOTE:** Depending on how the user is interacting with the web server, certain data will be expected to be in this section, **;** delimited, in some order, what kind of data and in what order is discussed in the **_Web Server_** section
