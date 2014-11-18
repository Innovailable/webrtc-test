palava = require("palava-client")
async = require("async")
$ = jquery = require('jquery')
require('string-format')
uuid = require('node-uuid')
query_string = require('query-string')
q = require('q')

current_url = () ->
  return window.location.href.split('?')[0]

class WebRtcTest

  constructor: (@frontend, options={}) ->
    @result = {}
    @errors = []

    @options = $.extend({
      url_base:     current_url()
      echo_server:  'http://gromit.local:3000/invite.json'
      stun:         'stun:stun.palava.tv'
      signaling:    'wss://machine.palava.tv'
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

    run_test = (invite, wait, finish) =>
      console.log 'running'

      steps = [
        @test_session
        invite or (cb) -> cb()
        @test_local
        @test_join
        wait or (cb) -> cb()
        @test_remote
        @test_data
        finish or (cb) -> cb()
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

    # which method to use?

    query = query_string.parse(location.search)

    if query.r?
      @room_id = query.r

      run_test(
        null
        (cb) => @wait_invited(cb)
        (cb) => @wait_finish(cb)
      )

      return

    @frontend.clear()
    @frontend.title("Test Setup")
    @frontend.prompt("Do you want to test with another person or using the echo server?")

    @frontend.add_button "Invite User", () =>
      run_test(
        (cb) => @invite_user(cb)
        (cb) => @wait_user(cb)
        (cb) => @wait_finish(cb)
      )

    @frontend.add_button "Echo Server", () =>
      run_test(
        null
        (cb) => @wait_echo(cb)
        null
      )


  # which test type?

  invite_user: (cb) ->
    html = 'Please ask the person you want to test with to visit the following page:<br />{0}'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Invite peer")
    @frontend.prompt_html(html)

    @frontend.add_button "Done", () ->
      cb()


  # internal

  test_session: (cb) ->
    if not @room_id?
      @room_id = uuid.v4()

    channel = new palava.WebSocketChannel(@options.signaling)

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

    use_peer = (peer) =>
      peer_d.resolve(peer)

      peer.on 'stream_ready', (stream) =>
        console.log peer
        remote_d.resolve(peer.getStream())

      peer.on 'stream_error', () =>
        remote_d.fail("Stream error")

    @session.on 'peer_joined', (peer) =>
      use_peer(peer)

    # room handling

    room_d = q.defer()
    @room_p = room_d.promise

    @session.on 'room_joined', (room) ->
      room_d.resolve(room)

      for id, peer of room.peers
        if not peer.isLocal()
          use_peer(peer)
          break

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

    @session.room.join()

    @room_p.timeout(10000).then(() ->
      cb()
    , (err) ->
      @fatal_error("Unable to join test room", cb)
    ).done()


  # test streams and data channels

  test_av: (type, finish) ->
    test_video = (cb) =>
      @frontend.clear_input()
      @frontend.prompt("Do you see an image?", cb)

      @frontend.add_button "Yes", () =>
        cb()

      @frontend.add_button "No", () =>
        @add_error("No {0} video".format(type))
        cb()

    test_audio = (cb) =>
      @frontend.clear_input()
      @frontend.prompt("Do you hear audio?", cb)

      @frontend.add_button "Yes", () =>
        cb()

      @frontend.add_button "No", () =>
        @add_error("No {0} audio".format(type))
        cb()

    async.series [
      test_video
      test_audio
    ], finish

  test_local: (cb) ->
    @frontend.clear()
    @frontend.title("Local Media Access")
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

    @local_p.then((stream) =>
      @frontend.video(stream)
      @test_av("local", cb)
    (err) =>
      @fatal_error("Local media access denied", cb)
    ).done()


  test_remote: (cb) ->
    @frontend.title("Remote Media")
    @frontend.prompt("Waiting for remote media to arrive ...")

    @remote_p.timeout(15000).then((stream) =>
      console.log stream
      @frontend.video(stream)
      @test_av("remote", cb)
    , (err) =>
      @fatal_error("Unable to receive remote data", cb)
    ).done()


  test_data: (cb) ->
    cb()
    #@fatal_error("Test not implemented, yet", cb)


  # waiting for remote
  
  wait_user: (cb) ->
    html = 'Waiting for other user. Please ask the person you want to test with to visit the following page:<br />{0}'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt_html(html)

    @remote_p.then((remote) ->
      cb()
    (err) ->
      # should never happen, no fail!
      @fatal_error("Peer unable to join", cb)
    ).done()


  wait_invited: (cb) ->
    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt('Waiting for other user. Please make sure that the other user did not abort the test.')

    @remote_p.then((remote) ->
      cb()
    (err) ->
      # should never happen, no fail!
      @fatal_error("Peer unable to join", cb)
    ).done()

  
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
        @peer_p.timeout(10000).then((peer) ->
          cb()
        (err) ->
          @fatal("Echo server did not respond", cb)
        ).done()
      error: () =>
        @fatal_error("Unable to contact echo server", cb)
    }


  wait_finish: (cb) ->
    @frontend.clear()
    @frontend.title("Waiting")
    @frontend.prompt("Please wait for your peer to finish testing.")

    @frontend.add_button "Done", cb


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
