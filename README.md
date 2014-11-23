# WebRTC Test

## What is this?

This is a WebRTC test page using the `palava-client` library. It is designed to
test whether WebRTC works on a specific device, help find bugs in the setup of
the user and identify bugs in the `palava-client` library.

## Usage

This project uses [wintersmith](http://wintersmith.io/) to generate static
content. To build the application install wintersmith and run:

    npm install
    wintersmith build

The generated files can be found in the `build` directory.

You can use environment variables to configure the mandatory and optional
dependencies and and configure the application. The following environment
variables are available:

* `URL_BASE`: the url under which the page will be available (for invitation
  links)
* `SIGNALING`: the signaling server (default: `wss://machine.palava.tv`)
* `STUN`: the stun server (default: `stun:stun.palava.tv`)
* `ECHO_SERVER`: address of the echo server (only invitation mode if not
  configured)

To build the page with the options do something like this:

    URL_BASE='http://webrtctest.example.com/' wintersmith build

