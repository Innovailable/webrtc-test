palava = require("palava-client")
async = require("async")
$ = jquery = require('jquery')
require('string-format')
uuid = require('node-uuid')
query_string = require('query-string')
q = require('q')

current_url = () ->
  return window.location.href.split('?')[0]

class MultiUserTest

  constructor: (@test) ->
    @frontend = @test.frontend


  finish: () ->
    @frontend.clear()
    @frontend.title("Waiting")
    @frontend.prompt("Please wait for your peer to finish testing.")

    defer = q.defer()

    @frontend.add_button "Done", () ->
      defer.resolve()

    return defer.promise


class InvitingTest extends MultiUserTest

  start: () ->
    html = 'Please ask the person you want to test with to visit the following page:<br />{0}'.format(@test.invite_url())

    @frontend.clear()
    @frontend.title("Invite peer")
    @frontend.prompt_html(html)

    defer = q.defer()

    @frontend.add_button "Done", () ->
      defer.resolve()

    return defer.promise


  wait: () ->
    html = 'Waiting for other user. Please ask the person you want to test with to visit the following page:<br />{0}'.format(@test.invite_url())

    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt_html(html)

    return @test.remote_p


class InvitedTest extends MultiUserTest

  start: () ->
    q.fcall(() =>)


  wait: () ->
    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt('Waiting for other user. Please make sure that the other user did not abort the test.')

    return @test.remote_p


class EchoTest

  constructor: (@test) ->
    @frontend = @test.frontend


  start: () ->
    q.fcall(() =>)


  wait: (cb) ->
    @frontend.clear()
    @frontend.title("Contacting Echo Server")
    @frontend.prompt("Waiting for connection with echo server ...")

    return q($.ajax({
      url: @test.options.echo_server
      type: 'POST'
      data: {
        room: @room_id
      }
    })).then () =>
      return @test.peer_p.timeout(10000)
    .fail () =>
      throw Error("Error inviting echo server")



  finish: (cb) ->
    q.fcall(() =>)


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


  fatal_error: (exception) ->
    text = exception.message

    console.log exception
    console.log exception.stack

    @add_error(text)

    @frontend.clear()
    @frontend.title("Error")
    @frontend.prompt("Sorry, a fatal error occured: " + text)

    defer = q.defer()

    @frontend.add_button "OK", () =>
      defer.resolve()

    return defer.promise


  invite_url: () ->
    return "{0}?r={1}".format(@options.url_base, @room_id)


  # start control flow of test

  start: () ->
    # actual flow

    q.when =>
      @test_webrtc()
    .then =>
      @test_method()
    .then =>
      @test_session()
    .then =>
      @method.start()
    .then =>
      @test_local()
    .then =>
      @test_join()
    .then =>
      @method.wait()
    .then =>
      @test_remote()
    .then =>
      @test_data()
    .then =>
      @method.finish()
    .fail (err) =>
      @fatal_error(err)
    .then =>
      @report()


  test_webrtc: () ->
    # check whether WebRTC is even available

    if palava.browser.checkForWebrtcError()
      throw Error("Your browser does not seem to support WebRTC")


  test_method: () ->
    # which method to use?

    query = query_string.parse(location.search)

    if query.r?
      @room_id = query.r

      @method = new InvitedTest(@)

      return q.fcall(() =>)

    @frontend.clear()
    @frontend.title("Test Setup")
    @frontend.prompt("Do you want to test with another person or using the echo server?")

    defer = q.defer()

    @frontend.add_button "Invite User", () =>
      @method = new InvitingTest(@)
      defer.resolve()

    @frontend.add_button "Echo Server", () =>
      @method = new EchoTest(@)
      defer.resolve()

    return defer.promise


  # internal

  test_session: () ->
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

    q.fcall(() =>)


  test_join: () ->
    @frontend.clear()
    @frontend.title("Joining")
    @frontend.prompt("Joining test room ...")

    @session.room.join()

    return @room_p.timeout(10000, "Unable to join test room")


  # test streams and data channels

  test_av: (type) ->
    test_video = () =>
      # video

      @frontend.clear_input()
      @frontend.prompt("Do you see an image?")

      defer = q.defer()

      @frontend.add_button "Yes", () =>
        defer.resolve()

      @frontend.add_button "No", () =>
        @add_error("No {0} video".format(type))
        defer.resolve()

      return defer.promise

    test_audio = () =>
      # audio

      @frontend.clear_input()
      @frontend.prompt("Do you hear audio?")

      defer = q.defer()

      @frontend.add_button "Yes", () =>
        defer.resolve()

      @frontend.add_button "No", () =>
        @add_error("No {0} audio".format(type))
        defer.resolve()

      return defer.promise

    return test_video().then(test_audio)


  test_local: () ->
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

    return @local_p.then (stream) =>
      @frontend.video(stream)
      return @test_av("local")
    .fail (err) =>
      console.log err
      throw Error("Local media access denied")


  test_remote: () ->
    @frontend.title("Remote Media")
    @frontend.prompt("Waiting for remote media to arrive ...")

    return @remote_p.timeout(15000).then (stream) =>
      @frontend.video(stream)
      return @test_av("remote")
    .fail (err) =>
      console.log err
      throw Error("Unable to receive remote data")


  test_data: () ->
    return q.fcall(() =>)
    #@fatal_error("Test not implemented, yet", cb)


  # reporting

  report: () ->
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


module.exports =
  WebRtcTest: WebRtcTest
