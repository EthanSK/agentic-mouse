import Foundation
import Darwin

/// Same-user feedback lets the receiver suppress cursor output only while
/// Agentic Mouse actually owns a persistent wand HUD. Never trust a stale lease.
enum WandContextSender {
    /// `switchAppAdjusting` is true only while home Switch App is in dotted
    /// mode with Command held by our key owner and a live unheld wand stream,
    /// so the receiver may continue it with circular winding.
    /// Older receivers ignore the extra key.
    static func send(active:Bool,appMode:String?=nil,reviewMode:String?=nil,reviewSelection:String?=nil,screenshotActive:Bool=false,switchAppAdjusting:Bool=false) {
        let path=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WandReceiver/context.sock").path
        var metadata=stat()
        guard lstat(path,&metadata)==0,metadata.st_uid==geteuid(),metadata.st_mode & S_IFMT == S_IFSOCK,
              metadata.st_mode & 0o077 == 0,
              let data=try? JSONSerialization.data(withJSONObject:["version":1,"active":active,"appMode":appMode ?? "","reviewMode":reviewMode ?? "","reviewSelection":reviewSelection ?? "","screenshotActive":screenshotActive,"switchAppAdjusting":active && switchAppAdjusting,"pid":getpid(),"sentAt":Date().timeIntervalSince1970]) else {return}
        let fd=socket(AF_UNIX,SOCK_DGRAM,0);guard fd>=0 else{return};defer{close(fd)}
        _=fcntl(fd,F_SETFL,O_NONBLOCK)
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
        let bytes=Array(path.utf8)+[0];guard bytes.count<=MemoryLayout.size(ofValue:address.sun_path) else{return}
        withUnsafeMutableBytes(of:&address.sun_path){$0.copyBytes(from:bytes)}
        address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        data.withUnsafeBytes {payload in
            withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {
                _=sendto(fd,payload.baseAddress,data.count,0,$0,socklen_t(MemoryLayout<sockaddr_un>.size))
            }}
        }
    }
}
