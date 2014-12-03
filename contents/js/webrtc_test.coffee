q = require('q')
ride = require('ride')

query_string = require('query-string')
uuid = require('node-uuid')
require('string-format')

$ = jquery = require('jquery')
palava = require("palava-client")
saveAs = require("filesaver.js")

current_url = () ->
  return window.location.href.split('?')[0]


# monkey patch some logging into palava peers

class palava.RemotePeer extends palava.RemotePeer

  constructor: (id, status, room, offers) ->
    @start = Date.now()

    @messages = []
    @states = []

    super(id, status, room, offers)

    ride(@distributor, 'send').before (data) =>
      @messages.push {
        time: @time()
        sender: "a"
        message: data
      }

    @distributor.channel.on 'message', (data) =>
      @messages.push {
        time: @time()
        sender: "b"
        message: data
      }

    ride(@peerConnection, 'oniceconnectionstatechange').before (event) =>
      @states.push {
        time: @time()
        type: 'ice'
        state: event.target.iceConnectionState
      }

    @peerConnection.onsignalingstatechange = (event) =>
      @states.push {
        time: @time()
        type: 'signaling'
        state: event.target.signalingState
      }


  time: () ->
    return Date.now() - @start


# the different test methods (echo, inviting and being invited)

class MultiUserTest

  name: "invite"


  constructor: (@test) ->
    @frontend = @test.frontend
    @test.result.clients.a.direction = @direction


  invite_url: () ->
    return "{0}?r={1}".format(@test.options.url_base, @test.room_id)


  finish: () ->
    @frontend.clear()
    @frontend.title("Peer still testing")
    @frontend.prompt("Please wait for your peer to finish testing.")

    return @test.peer_p.then (peer) =>
      peer.sendMessage {
        type: 'test_finish'
        data: @test.result.clients.a
      }

      return @finish_d.promise
    .then (data) =>
      @test.result.clients.b = data
      return q()


  wait_connect: () ->
    return @test.peer_p.then (peer) =>
      return @start_d.promise.timeout(5000, "Unable to test with peer")


  init_peer: (peer) ->
    @start_d= q.defer()
    @finish_d= q.defer()

    peer.on 'message', (data) =>
      console.log 'message!'
      console.log data

      if data.type == 'test_start'
        @start_d.resolve()

      if data.type == 'test_finish'
        @finish_d.resolve(data.data)

    peer.sendMessage {
      type: 'test_start'
    }


class InvitingTest extends MultiUserTest

  direction: "inviting"


  start: () ->
    html = 'Please ask the person you want to test with to visit the page below. Please note that data will be exchanged during the test to create a debug log.<br /><span>{0}</span>'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Invite peer")
    @frontend.prompt_html(html)

    defer = q.defer()

    @frontend.add_button "Done", () ->
      defer.resolve()

    return defer.promise


  wait: () ->
    html = 'Waiting for other user. Please ask the person you want to test with to visit the following page:<br /><span>{0}</span>'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt_html(html)

    return @wait_connect()


class InvitedTest extends MultiUserTest

  direction: "invited"


  start: () ->
    defer = q.defer()

    @frontend.clear()
    @frontend.title("Multiuser Test")
    @frontend.prompt("You are about to test the WebRTC abilities of your browser together with the person who sent you the link. Please note that data will be exchanged during the test to create a debug log.")

    @frontend.add_button "Ok", () =>
      defer.resolve()

    return defer.promise


  wait: () ->
    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt('Waiting for other user. Please make sure that the other user did not abort the test.')

    console.log 'invited waiting'

    return @wait_connect()


class EchoTest

  name: "echo"


  constructor: (@test) ->
    @frontend = @test.frontend


  start: () ->
    q()


  wait: (cb) ->
    @frontend.clear()
    @frontend.title("Contacting Echo Server")
    @frontend.prompt("Waiting for connection with echo server ...")

    return q($.ajax({
      url: @test.options.echo_server
      type: 'POST'
      data: {
        room: @test.room_id
      }
    })).then () =>
      return @test.peer_p.timeout(10000)
    .fail () =>
      throw Error("Error inviting echo server")


  finish: (cb) ->
    q()


# the actual test code

class WebRtcTest

  constructor: (@frontend, options={}) ->
    @result = {
      time: Date.now()
      clients:
        a:
          useragent: navigator.userAgent
    }

    @errors = []

    @options = $.extend({
      url_base:     current_url()
      echo:         null
      report:       null
      signaling:    'wss://machine.palava.tv'
      stun:         'stun:stun.palava.tv'
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
      @get_peer_states()
    .then =>
      @method.finish()
    .then =>
      @get_signaling()
    .fail (err) =>
      @fatal_error(err)
    .then =>
      @report()
    .done()


  test_webrtc: () ->
    # check whether WebRTC is even available

    if palava.browser.checkForWebrtcError()
      throw Error("Your browser does not seem to support WebRTC")


  test_method: () ->
    # which method to use?

    query = query_string.parse(location.search)

    # we are invited

    if query.r?
      @room_id = query.r

      @method = new InvitedTest(@)

      return q()

    # no echo server and not invited ... we have to invite

    if not @options.echo_server
      @method = new InvitingTest(@)
      return q()

    # ask user

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
    @result.method = @method.name

    if not @room_id?
      @room_id = uuid.v4()

    if typeof @options.signaling == 'string'
      channel = new palava.WebSocketChannel(@options.signaling)
    else
      channel = @options.signaling

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

    data_channel_d = q.defer()
    @data_channel_p = data_channel_d.promise

    data_data_d = q.defer()
    @data_data_p = data_data_d.promise

    use_peer = (peer) =>
      if not @peer_p.isPending()
        return

      peer_d.resolve(peer)

      @method.init_peer?(peer)

      peer.on 'stream_ready', (stream) =>
        remote_d.resolve(peer.getStream())

      peer.on 'stream_error', () =>
        remote_d.fail("Stream error")

      peer.on 'channel_ready', (name, channel) =>
        if name != 'test'
          return

        data_channel_d.resolve()

        test_msg = "hello world"

        channel.send(test_msg)

        channel.on 'message', (data) =>
          if data == test_msg
            data_data_d.resolve()
          else
            data_data_d.fail("Data channel data mismatch")

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

    q()


  test_join: () ->
    @frontend.clear()
    @frontend.title("Joining")
    @frontend.prompt("Joining test room ...")

    @session.room.join()

    return @room_p.timeout(10000, "Unable to join test room")


  # test streams and data channels

  test_av: (stream, type, res) ->
    test_video = () =>
      # video

      if stream.getVideoTracks().length == 0
        res.stream.video = false
        return q()

      res.stream.video = true

      @frontend.clear_input()
      @frontend.prompt("Do you see an image?")

      defer = q.defer()

      @frontend.add_button "Yes", () =>
        res.user.video = true
        defer.resolve()

      @frontend.add_button "No", () =>
        res.user.video = false
        @add_error("No {0} video".format(type))
        defer.resolve()

      return defer.promise

    test_audio = () =>
      # audio

      if stream.getAudioTracks().length == 0
        res.stream.audio = false
        return q()

      res.stream.audio = true

      @frontend.clear_input()
      @frontend.prompt("Do you hear audio?")

      defer = q.defer()

      @frontend.add_button "Yes", () =>
        res.user.audio = true
        defer.resolve()

      @frontend.add_button "No", () =>
        res.user.audio = false
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

    res = @result.clients.a.local = {
      stream:
        ready: false
      user: {}
    }

    return @local_p.then (stream) =>
      res.stream.ready = true
      @frontend.video(stream)
      return @test_av(stream, "local", res)
    .fail (err) =>
      throw Error("Local media access denied")


  test_remote: () ->
    @frontend.clear()
    @frontend.title("Remote Media")
    @frontend.prompt("Waiting for remote media to arrive ...")

    res = @result.clients.a.remote = {
      stream:
        ready: false
      user: {}
    }

    video_ready_d = q.defer()

    return @remote_p.timeout(30000, "Unable to receive remote stream").then (stream) =>
      res.stream.ready = true

      video = @frontend.video(stream)

      if video.readyState >= 2
        video_ready_d.resolve(stream)
      else
        video.oncanplay = ->
          video_ready_d.resolve(stream)

      return video_ready_d.promise.timeout(10000, "Unable to start remote stream")
    .then (stream) =>
      return @test_av(stream, "remote", res)
    .fail (err) =>
      console.log err
      @add_error(err)
      return q()


  test_data: () ->
    @frontend.clear()
    @frontend.title("Data Channel")
    @frontend.prompt("Waiting for data channel to arrive ...")

    res = @result.clients.a.data = {
      channel: false
      data: false
    }

    return @data_channel_p.timeout(5000, "Unable to open data channel").then () =>
      @frontend.prompt("Waiting for data channel data to arrive ...")
      res.channel = true
      return @data_data_p.timeout(5000, "Data channel did not receive data")
    .then () =>
      res.data = true
      return q()
    .fail (err) =>
      # error is not fatal, save it and go on
      @add_error(err.message)
      return q()



  get_peer_states: () ->
    return @peer_p.then (peer) =>
      @result.clients.a.states = peer.states


  get_signaling: () ->
    return @peer_p.then (peer) =>
      @result.signaling = peer.messages


  # reporting

  report: () ->
    reporting = !!@options.report

    @session.destroy()

    @frontend.clear()
    @frontend.title("Test complete")

    if reporting
      html = "<div>Thanks for testing. Please press the button below to report the results to the developers.</div>"
    else
      html = "<div>Thanks for testing.</div>"

    if @errors.length
      error_list = $('<ul>')

      for error in @errors
        error_list.append($('<li>').text(error))

      html += error_list.html()
    else
      html += "<div>No errors detected</div>"

    @frontend.prompt_html(html)

    @frontend.add_button "Save technical log", () =>
      report = JSON.stringify(@result, null, '\t')
      blob = new Blob([report], {type: "text/plain;charset=utf-8"})
      saveAs(blob, "webrtc_test_report.json")

    if reporting
      @frontend.add_button "Send report", () =>
        console.log "Reporting ... someday"

        # TODO

        @frontend.clear()
        @frontend.title("Thanks!")
        @frontend.prompt("Thanks for sending the report! Well  ... actually reporting does not work, yet. But thanks anyway.")


module.exports =
  WebRtcTest: WebRtcTest
