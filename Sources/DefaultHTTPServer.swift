//
//  DefaultHTTPServer.swift
//  Embassy
//
//  Created by Fang-Pen Lin on 5/19/16.
//  Copyright © 2016 Fang-Pen Lin. All rights reserved.
//

import Foundation
import Dispatch

public final class DefaultHTTPServer: HTTPServer,HTTPConnectionDelegate {
    public let logger = DefaultLogger()
    public var app: SWSGI

    /// Interface of TCP/IP to bind
    public let interface: String
    /// Port of TCP/IP to bind
    public let port: Int

    // the socket for accepting incoming connections
    private var acceptSocket: TCPSocket!
    private let eventLoop: EventLoop
    private var connections = Set<HTTPConnection>()

    public init(
        eventLoop: EventLoop,
        interface: String = "::1",
        port: Int = 0,
        app: @escaping SWSGI
    ) {
        self.eventLoop = eventLoop
        self.app = app
        self.interface = interface
        self.port = port
    }

    deinit {
        stop()
    }

    public var listenAddress: (host: String, port: Int) {
        return try! acceptSocket.getSockName()
    }

    public func start() throws {
        guard acceptSocket == nil else {
            logger.error("Server already started")
            return
        }
        logger.info("Starting HTTP server on [\(interface)]:\(port) ...")
        acceptSocket = try TCPSocket()
        try acceptSocket.bind(port: port, interface: interface)
        try acceptSocket.listen()
        try eventLoop.setReader(acceptSocket.fileDescriptor) { [unowned self] in
            self.handleNewConnection()
        }
        logger.info("HTTP server running")
    }

    public func stop() {
        guard acceptSocket != nil else {
            logger.error("Server not started")
            return
        }
        try? eventLoop.removeReader(acceptSocket.fileDescriptor)
        acceptSocket.close()
        for connection in connections {
            connection.close()
        }
        connections = []
        logger.info("HTTP server stopped")
    }

    public func stopAndWait() {
        let semaphore = DispatchSemaphore(value: 0)
        eventLoop.call {
            self.stop()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: DispatchTime.distantFuture)
    }

    // called to handle new connections
    private func handleNewConnection() {
        let clientSocket = try! acceptSocket.accept()
        let (address, port) = try! clientSocket.getPeerName()
        let transport = Transport(socket: clientSocket, eventLoop: eventLoop)
        let connection = HTTPConnection(
            app: appForConnection,
            serverName: "[\(interface)]",
            serverPort: self.port,
            transport: transport,
            eventLoop: eventLoop,
            logger: logger
        )
        connections.insert(connection)
        connection.delegate = self
        logger.info("New connection \(connection.uuid) from [\(address)]:\(port)")
    }
    
    public func closedCallback(_ connection:HTTPConnection) {
        connections.remove(connection)
    }
    
    private func appForConnection(
        _ environ: [String: Any],
        startResponse: @escaping ((String, [(String, String)]) throws-> Void),
        sendBody: @escaping ((Data) throws-> Void)
    ) {
        app(environ, startResponse, sendBody)
    }

}
