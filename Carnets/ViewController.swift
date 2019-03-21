//
//  ViewController.swift
//  Carnets
//
//  Created by Nicolas Holzschuch on 26/01/2019.
//  Copyright © 2019 AsheKube. All rights reserved.
//

import UIKit
import WebKit
import UserNotifications
import ios_system

var serverAddress: URL!
// The URL for the file being accessed (can be distant):
public var notebookURL: URL?
// A bookmark to the file being accessed (in case it changes name):
var notebookBookmark: Data?
// The URL for the notebook: http://localhost:8888/notebooks/Documents/file if local file
// http://localhost:8888/notebooks/tmp/(A Document Being Saved by Carnets 5)/file if distant
public var kernelURL: URL?
public var startingPath: String?
var appWebView: WKWebView!

var bookmarks: [URL: Data] = [:]
var localFiles: [URL: URL] = [:]


extension String {
    
    func toCString() -> UnsafePointer<Int8>? {
        let nsSelf: NSString = self as NSString
        return nsSelf.cString(using: String.Encoding.utf8.rawValue)
    }
    
    var utf8CString: UnsafeMutablePointer<Int8> {
        return UnsafeMutablePointer(mutating: (self as NSString).utf8String!)
    }
    
}

func convertCArguments(argc: Int32, argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?) -> [String]? {
    
    var args = [String]()
    
    for i in 0..<Int(argc) {
        
        guard let argC = argv?[i] else {
            return nil
        }
        
        let arg = String(cString: argC)
        
        args.append(arg)
        
    }
    
    return args
}

// load notebook sent by documentBrowser:
func urlFromFileURL(fileURL: URL) -> URL {
    var returnURL = serverAddress
    if (kernelURL != nil) {
        returnURL = kernelURL
    }
    guard (fileURL.isFileURL) else {
        return returnURL!
    }
    var filePath = fileURL.path
    if (filePath.hasPrefix("/private") && (!startingPath!.hasPrefix("/private"))) {
        filePath = String(filePath.dropFirst("/private".count))
    }
    if (filePath.hasPrefix(startingPath!)) {
        if (!FileManager().fileExists(atPath: filePath)) {
        // Don't try to open files that don't exist
            return returnURL!
        }
    } else {
        // Non-local file. Copy into ~/tmp/ and open
        // first, is that the last file we opened?
        var fileURLToOpen:URL?
        var destination:URL?
        if (notebookBookmark == nil) {
            notebookBookmark = UserDefaults.standard.data(forKey: "lastOpenUrlBookmark")
            if (notebookBookmark != nil) {
                var stale = false
                do {
                    let previousURL = try URL(resolvingBookmarkData: notebookBookmark!, bookmarkDataIsStale: &stale)
                    if (!stale && (previousURL.path == fileURL.path)) {
                            // They are the same, but the one from the bookmark still has the authorization
                            fileURLToOpen = previousURL
                            bookmarks.updateValue(notebookBookmark!, forKey:fileURLToOpen!)
                    }
                } catch {
                    NSLog("Could not resolve the bookmark to previous URL")
                    print(error)
                }
            }
        }
        if (fileURLToOpen == nil) {
            // Not the bookmark stored in UserDefaults, maybe in the dictionary?
            if (bookmarks[fileURL] != nil) {
                // We've met this one before
                var stale = false
                do {
                    let previousURL = try URL(resolvingBookmarkData: bookmarks[fileURL]!, bookmarkDataIsStale: &stale)
                    if (!stale && (previousURL.path == fileURL.path)) {
                        // We did this URL before, and still have the bookmark for it
                        fileURLToOpen = previousURL
                        notebookBookmark = bookmarks[fileURL]
                    }
                } catch {
                    NSLog("Could not resolve the bookmark to previous URL")
                    print(error)
                }
            }
        }
        // no existing bookmarks, so we take the URL given:
        if (fileURLToOpen == nil) {
            fileURLToOpen = fileURL
            notebookBookmark = nil  // if we're there, we don't have a bookmark
        }
        destination = localFiles[fileURL]
        if (destination == nil) {
            // do we have a local file storage:
            let temporaryDirectory = try! FileManager().url(for: .itemReplacementDirectory,
                                                            in: .userDomainMask,
                                                            appropriateFor: URL(fileURLWithPath: startingPath!),
                                                            create: true)
            destination = temporaryDirectory.appendingPathComponent(fileURLToOpen!.lastPathComponent)
            localFiles.updateValue(destination!, forKey:fileURLToOpen!)
        }
        let isSecuredURL = fileURLToOpen!.startAccessingSecurityScopedResource() == true
        do {
            // Specific treatment for files on iCloud that are not downloaded:
            if (!FileManager().fileExists(atPath: fileURLToOpen!.path)) {
                NSLog("Downloading file from iCloud: \(fileURLToOpen)")
                try FileManager().startDownloadingUbiquitousItem(at: fileURLToOpen!)
                let startingTime = Date()
                // try downloading the file for 5s, then give up:
                while (!FileManager().fileExists(atPath: fileURLToOpen!.path) && (Date().timeIntervalSince(startingTime) < 5)) { }
                // TODO: add an alert, ask if user wants to continue
                NSLog("Done downloading, new status: \(FileManager().fileExists(atPath: fileURLToOpen!.path))")
            }
            if (notebookBookmark == nil) {
                notebookBookmark = try fileURLToOpen!.bookmarkData(options: [],
                                                                   includingResourceValuesForKeys: nil,
                                                                   relativeTo: nil)
                bookmarks.updateValue(notebookBookmark!, forKey:fileURLToOpen!)
            }
            UserDefaults.standard.set(notebookBookmark, forKey: "lastOpenUrlBookmark")
            if (FileManager().fileExists(atPath: destination!.path)) {
                try FileManager().removeItem(atPath: destination!.path)
            }
            try FileManager().copyItem(at: fileURLToOpen!, to: destination!)
        }
        catch {
            print(error)
            if (isSecuredURL) {
                fileURLToOpen!.stopAccessingSecurityScopedResource()
            }
            return returnURL!
        }
        if (isSecuredURL) {
            fileURLToOpen!.stopAccessingSecurityScopedResource()
        }
        filePath = destination!.path
        if (filePath.hasPrefix("/private") && (!startingPath!.hasPrefix("/private"))) {
            filePath = String(filePath.dropFirst("/private".count))
        }
    }
    // local files.
    filePath = String(filePath.dropFirst(startingPath!.count))
    if (filePath.hasPrefix("/")) { filePath = String(filePath.dropFirst()) }
    while (serverAddress == nil) {  }
    var fileAddressUrl = serverAddress.appendingPathComponent("notebooks")
    fileAddressUrl = fileAddressUrl.appendingPathComponent(filePath)
    return fileAddressUrl
}


/*
 override func fileAttributesToWrite(to url: URL, for saveOperation: UIDocumentSaveOperation) throws -> [AnyHashable : Any] {
 let thumbnail = thumbnailForDocument(at: url) return [
 URLResourceKey.hasHiddenExtensionKey: true, URLResourceKey.thumbnailDictionaryKey: [
 URLThumbnailDictionaryItem.NSThumbnail1024x1024SizeKey: thumbnail ]
 ] }
 */


func saveDistantFile() {
    var localFilePath = kernelURL!.path
    localFilePath = String(localFilePath.dropFirst("/notebooks".count))
    if (localFilePath.hasPrefix("/tmp")) {
        guard (notebookBookmark != nil) else { return }
        localFilePath = startingPath!.appending(localFilePath)
        do {
            var stale = false
            notebookURL = try URL(resolvingBookmarkData: notebookBookmark!, bookmarkDataIsStale: &stale)
            if (notebookURL != nil) {
                let temporaryDirectory = try! FileManager().url(for: .itemReplacementDirectory,
                                                                in: .userDomainMask,
                                                                appropriateFor: URL(fileURLWithPath: startingPath!),
                                                                create: true)
                var destination = temporaryDirectory
                destination = destination.appendingPathComponent(kernelURL!.lastPathComponent)
                try FileManager().copyItem(at: URL(fileURLWithPath: localFilePath), to: destination)
                notebookURL!.startAccessingSecurityScopedResource()
                try FileManager().replaceItemAt(notebookURL!, withItemAt: destination, backupItemName: nil, options: [])
                notebookURL!.stopAccessingSecurityScopedResource()
                try FileManager().removeItem(at: temporaryDirectory)
                NSLog("Saved distant file \(notebookURL!)")
            }
        }
        catch {
            print(error)
            NSLog("Could not save distant file \(notebookURL!)")
        }
    }
}


@_cdecl("openURL_internal")
public func openURL_internal(argc: Int32, argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?) -> Int32 {
    let usage = """
                usage: openurl url

                loads the specified url in the WkWebView of the application
                """

    guard let args = convertCArguments(argc: argc, argv: argv) else {
        fputs(usage, thread_stderr)
        return 1
    }
    var url: URL? = nil
    
    if args.count == 2 {
        url = URL(string: args[1])
    }
    
    guard url != nil else {
        fputs(usage, thread_stderr)
        return 1
    }
    NSLog("%@", "Server address is set to ".appending(args[1]))
    
    serverAddress = url
    guard (notebookURL != nil) else { return 0 }

    kernelURL = urlFromFileURL(fileURL: notebookURL!)
    appWebView.load(URLRequest(url: kernelURL!))
    return 0
}

// compare 2 URLs and return true if they correspond to the same
// page, excluding parameters and queries. This avoids infinite
// loops with redirections.
// Maybe we need to include parameters, but queries are excluded.
// We had an infinite loop with http://localhost:8888/nbextensions/
// loading http://localhost:8888/nbextensions/?nbextension=zenmode/main
func sameLocation(url1: URL?, url2: URL?) -> Bool {
    if (url1 == nil) && (url2 == nil) { return true }
    if (url1 == nil) { return false }
    if (url2 == nil) { return false }
    if (url1!.host != url2!.host) { return false }
    if (url1!.port != url2!.port) { return false }
    if (url1!.path != url2!.path) { return false }
    return true
}


class ViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let cmd:String = message.body as! String
        if (cmd == "quit") {
            // Warn the main app that the user has pressed the "quit" button
            clearAllRunningSessions()
            NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: notificationQuitRequested)))
        } else if (cmd == "save") {
            // if the file open is from another App, we copy the newly saved file too
            saveDistantFile()
        } else if (cmd == "back") {
            if self.webView.canGoBack {
                var position = -1
                var backPageItem = self.webView.backForwardList.item(at: position)
                while ((backPageItem != nil) && (sameLocation(url1: backPageItem?.url, url2: self.webView.url))) {
                    position -= 1
                    backPageItem = self.webView.backForwardList.item(at: position)
                }
                if (backPageItem != nil) {
                    self.webView.go(to: backPageItem!)
                    return
                }
            }
            // Nothing left in history, so we open the file server:
            var treeAddress = serverAddress
            treeAddress = treeAddress?.appendingPathComponent("tree")
            self.webView.load(URLRequest(url: treeAddress!))
        } else if (cmd.hasPrefix("loadingSession:")) {
            NSLog(cmd)
            addRunningSession(session: cmd, url: self.webView!.url!)
            if (numberOfRunningSessions() >= 4) { // Maybe "> 4"?
                NSLog("More than 4 notebook running (including this one). Time to cleanup.")
                var oldestSessionURL = oldestRunningSessionURL()
                var oldestSessionID = sessionID(url: oldestSessionURL)
                while (oldestSessionID == nil) {
                    NSLog("Oldest session URL was not stored. Taking the next one")
                    removeRunningSession(url: oldestSessionURL)
                    oldestSessionURL = oldestRunningSessionURL()
                    oldestSessionID = sessionID(url: oldestSessionURL)
                }
                let urlDelete = serverAddress!.appendingPathComponent(oldestSessionID!)
                var urlDeleteRequest = URLRequest(url: urlDelete)
                urlDeleteRequest.httpMethod = "DELETE"
                urlDeleteRequest.setValue("json", forHTTPHeaderField: "dataType")
                let task = URLSession.shared.dataTask(with: urlDeleteRequest) { data, response, error in
                    if let error = error {
                        NSLog ("Error on DELETE: \(error)")
                        return
                    }
                    guard let response = response as? HTTPURLResponse,
                        (200...299).contains(response.statusCode) else {
                            NSLog ("Server error on DELETE")
                            return
                    }
                    removeRunningSession(url: oldestSessionURL)
                }
                task.resume()
            }
        } else if (cmd.hasPrefix("killingSession:")) {
            NSLog(cmd)
            var key = cmd
            key.removeFirst("killingSession:".count)
            if (key.hasPrefix("/")) {
                key = String(key.dropFirst())
            }
            removeRunningSessionWithID(session: key)
        } else {
            // JS console:
            NSLog("JavaScript message: \(message.body)")
        }
    }
        
    var webView: WKWebView!
    var lastPageVisited: String!
    var tbAccessoryView : UIToolbar?

    override func loadView() {
        let contentController = WKUserContentController();
        contentController.add(self, name: "Carnets")
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "shouldAllowUserInstalledFonts")
        
        webView = WKWebView(frame: .zero, configuration: config)
        
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view = webView
        appWebView = webView
    }
    
    // This works in text-input mode:
    @objc func escapeKey() {
        print("Received escape key")
    }
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: .shift, action: #selector(escapeKey), discoverabilityTitle: "Escape Key")
        ]
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        webView.allowsBackForwardNavigationGestures = true
        // in case Jupyter has started before the view is active (unlikely):
        guard (serverAddress != nil) else { return }
        guard (notebookURL != nil) else { return }
        kernelURL = urlFromFileURL(fileURL: notebookURL!)
        webView.load(URLRequest(url: kernelURL!))
    }
    
    @objc
    func doBtnPrev() {
        
    }
    
    @objc
    func doBtnNext() {
        
    }
    
    @objc
    func doBtnSubmit() {
        
    }
    
}



// This function is called when the user clicks on a link inside the App
// This is where we should replace webView.load (for internal action)
// with openurl_main to open in external browsers. Also Juno, when it
// has a specific URL scheme. 
extension ViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.stopLoading()
            webView.load(navigationAction.request)
        }
        return nil
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Method called after a web page has been loaded, including as a result of goBack()
        // or goForward().
        // More accurate to store the latest URL accessed than navigationAction()
        guard (webView.url != nil) else { return }
        NSLog("Trying to load: \(webView.url)")
        if (webView.url!.path.starts(with: "/api/")) { return }  // don't store api requests
        if (webView.url!.path == "/tree") {
            // We're leaving. Copy edited file back to place and remove directory:
            saveDistantFile()
            UserDefaults.standard.set(nil, forKey: "lastOpenUrl")
            UserDefaults.standard.set(nil, forKey: "lastOpenUrlBookmark")
            notebookURL = nil
            kernelURL = nil
            dismiss(animated: true) // back to documentBrowser
        } else {
            guard(webView.url != nil) else { return }
            kernelURL = webView.url
            var fileLocation = kernelURL!.path
            fileLocation.removeFirst("/notebooks/".count)
            var fileLocationURL = URL(fileURLWithPath: startingPath!)
            if (fileLocation.starts(with: "Documents")) {
                // local file
                notebookURL = fileLocationURL.appendingPathComponent(fileLocation)
            } else {
                // distant file. Must find distant location, using stored information
                for (notebookURLStored, kernelURLStored) in localFiles {
                    var kernelURLStoredPath = kernelURLStored.path
                    if (kernelURLStoredPath.hasPrefix("/private") && (!startingPath!.hasPrefix("/private"))) {
                        kernelURLStoredPath = String(kernelURLStoredPath.dropFirst("/private".count))
                    }
                    if (kernelURLStoredPath.hasPrefix(startingPath!)) {
                        kernelURLStoredPath = String(kernelURLStoredPath.dropFirst(startingPath!.count))
                    }
                    if (kernelURLStoredPath.hasPrefix("/")) { kernelURLStoredPath = String(kernelURLStoredPath.dropFirst()) }
                    if (kernelURLStoredPath == fileLocation) {
                        notebookURL = notebookURLStored
                        break
                    }
                }
            }
            UserDefaults.standard.set(notebookURL, forKey: "lastOpenUrl")
            setSessionAccessTime(url: webView.url!)
        }
    }
}
