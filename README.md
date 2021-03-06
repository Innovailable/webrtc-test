# WebRTC Test

## What is this?

This is a WebRTC test page using the
[palava-client](https://github.com/palavatv/palava-client) library. It is
designed to test whether WebRTC works on a specific device, help find bugs in
the setup of the user and identify bugs in the `palava-client` library.

## Usage

This project uses [wintersmith](http://wintersmith.io/) to generate static
content. Install wintersmith and the dependencies of
this package:

    [sudo] npm install -g wintersmith
    npm install

To build the static files which you can deploy:

    wintersmith build

The generated files can be found in the `build` directory.

Wintersmith also has a preview mode, which will start a webserver that builds
the files on the fly:

    wintersmith preview

You can use environment variables to configure the mandatory and optional
dependencies and and configure the application. The following environment
variables are currently available:

* `URL_BASE`: the url under which the page will be available (for invitation
  links)
* `SIGNALING`: the signaling server (default: `wss://signaling.innovailable.eu`)
* `STUN`: the stun server (default: `stun:stun.palava.tv`)
* `ECHO`: address of the echo server (only invitation mode if not
  configured)

To build the page with the options do something like this:

    URL_BASE='http://webrtctest.example.com/' wintersmith build

*NOTE*: The application depends on some signaling server and palava-client
features which are neither in the current release nor deployed on
[palava.tv](https://palava.tv) at the time of writing.

