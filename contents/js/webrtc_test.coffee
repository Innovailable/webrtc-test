palava = require("palava-client")
async = require("async")
$ = jquery = require('jquery')
require('string-format')
uuid = require('node-uuid')
q = require('q')

class WebRtcTest

  constructor: (@frontend, options={}) ->
    @result = {}
    @errors = []

    @options = $.extend({
      url_base: 'http://example.com/'
      echo_server: 'http://gromit.local:3000/invite.json'
      stun: 'stun:stun.palava.tv'
    }, options)

    @start()

  # helper

  add_error: (text) ->
    @errors.push(text)

  fatal_error: (text, cb) ->
    @add_error(text)

    @frontend.clear()
    @frontend.title("Error")
    @frontend.prompt("Sorry, a fatal error occured: " + text)

    @frontend.add_button "OK", () =>
      cb(new Error(text))

  invite_url: () ->
    return "{0}?r={1}".format(@options.url_base, @room_id)

  # start control flow of test

  start: () ->
    # actual flow

    run_test = (invite, wait) =>
      console.log 'running'

      steps = [
        @test_init
        invite
        @test_local
        @test_join
        wait
        @test_remote
        @test_data
      ]

      done = (err) =>
        if err
          console.log(err)
        @report()

      async.series (fun.bind(@) for fun in steps), done

    # check whether WebRTC is even available

    if palava.browser.checkForWebrtcError()
      @fatal_error("Your browser does not seem to support WebRTC", cb)
      return

    # ask user which method to use

    @frontend.clear()
    @frontend.title("Test Setup")
    @frontend.prompt("Do you want to test with another person or using the echo server?")

    @frontend.add_button "Invite User", () =>
      run_test(
        (cb) => @invite_user(cb)
        (cb) => @wait_user(cb)
      )

    @frontend.add_button "Echo Server", () =>
      run_test(
        (cb) => cb()
        (cb) => @wait_echo(cb)
      )


  # which test type?

  invite_user: (cb) ->
    html = 'Waiting for other user. Please ask the person you want to test with to visit the following page:<br />{0}'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Invite peer")
    @frontend.prompt_html(html)

    @frontend.add_button "Done", () ->
      cb()


  # internal

  test_init: (cb) ->
    @room_id = uuid.v4()

    channel = new palava.WebSocketChannel('wss://machine.palava.tv')

    @session = new palava.Session
      roomId: @room_id
      channel: channel
      dataChannels:
        test:
          ordered: true

    # peer handling

    peer_d = q.defer()
    @peer_p = peer_d.promise

    remote_d = q.defer()
    @remote_p = remote_d.promise

    @session.on 'peer_joined', (peer) =>
      peer_d.resolve(peer)

      peer.on 'stream_ready', (stream) =>
        remote_d.resolve(stream)

      peer.on 'stream_error', () =>
        remote_d.fail("Stream error")


    # local stream handling

    local_d = q.defer()
    @local_p = local_d.promise

    @session.on 'local_stream_ready', (stream) =>
      local_d.resolve(stream)

    @session.on 'local_stream_error', () =>
      local_d.reject(new Error("Local stream error"))

    cb()


  test_join: (cb) ->
    @frontend.clear()
    @frontend.title("Joining")
    @frontend.prompt("Joining test room ...")

    console.log 'a'

    deferred = q.defer()

    console.log 'b'

    @session.on 'room_joined', () ->
      console.log 'joined'
      deferred.resolve(true)

    console.log 'joining?'
    @session.room.join()
    console.log 'joining!'

    deferred.promise.timeout(10000).then () ->
      console.log "yuppp"
      cb()
    , (err) ->
      @fatal_error("Unable to join test room", cb)


  # test streams and data channels

  test_local: (cb) ->
    @frontend.clear()
    @frontend.title("Media Access")
    @frontend.prompt("Your browser should ask you whether you want to grant this site access to your camera and microphone")

    @session.init
      identity: new palava.Identity
        userMediaConfig:
          audio: true
          video: true
        name: "Tester"
      options:
        stun: @options.stun
        joinTimeout: 500

    @local_p.then (stream) ->
      cb()
    (err) ->
      cb(err)


  test_remote: (cb) ->
    @remote_p.timeout(15000).then (stream) =>
      cb()
    , (err) =>
      @fatal_error("Unable to receive remote data", cb)


  test_data: (cb) ->
    cb()
    #@fatal_error("Test not implemented, yet", cb)


  # waiting for remote
  
  wait_user: (cb) ->
    html = 'Waiting for other user. Please ask the person you want to test with to visit the following page:<br /><a href="{0}">{0}</a>'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt_html(html)

    @remote_p.then (remote) ->
      cb()
    (err) ->
      @fatal_error("Access to local media denied", cb)

  
  wait_echo: (cb) ->
    @frontend.clear()
    @frontend.title("Contacting Echo Server")
    @frontend.prompt("Waiting for connection with echo server ...")

    $.ajax {
      url: @options.echo_server
      type: 'POST'
      data: {
        room: @room_id
      }
      success: () =>
        @peer_p.timeout(10000).then (peer) ->
          cb()
        (err) ->
          @fatal("Echo server did not respond", cb)
      error: () =>
        @fatal_error("Unable to contact echo server", cb)
    }


  # reporting

  report: (cb) ->
    @session.destroy()

    @frontend.clear()
    @frontend.title("Test complete")

    html = "<div>Thanks for testing. Please press the button below to report the results to the developers.</div>"

    if @errors.length
      error_list = $('<ul>')

      for error in @errors
        error_list.append($('<li>').text(error))

      html += error_list.html()
    else
      html += "<div>No errors detected</div>"

    @frontend.prompt_html(html)

    @frontend.add_button "Send report", () =>
      console.log "Reporting ... someday"

      # TODO

      @frontend.clear()
      @frontend.title("Thanks!")
      @frontend.prompt("Thanks for sending the report! Well  ... actually reporting does not work, yet. But thanks anyway.")

      cb()


module.exports =
  WebRtcTest: WebRtcTest
