import Cocoa
import Darwin
import FlutterMacOS

/// Reads each core's cumulative CPU tick counters, which no command-line
/// tool prints: `top` only reports a percentage, and its first sample is
/// not measured over any window at all. Status computes usage from the
/// difference between two reads, the way Mole does through gopsutil's
/// `cpu.Times` (`cmd/status/metrics_cpu.go`), which calls this same
/// `host_processor_info`.
final class CpuTicksChannel {
  static let channelName = "fit.hoopix/cpu_ticks"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      Self.handle(call, result: result)
    }
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "read" else {
      result(FlutterMethodNotImplemented)
      return
    }

    var processorCount: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    let status = host_processor_info(
      mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount)
    guard status == KERN_SUCCESS, let info else {
      result(
        FlutterError(
          code: "host_processor_info",
          message: "host_processor_info failed with status \(status)",
          details: nil))
      return
    }
    defer {
      vm_deallocate(
        mach_task_self_,
        vm_address_t(bitPattern: info),
        vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
    }

    // Each core is CPU_STATE_MAX consecutive counters, stored as integer_t
    // but counting as unsigned 32-bit values that wrap.
    var cores: [[Int]] = []
    for core in 0..<Int(processorCount) {
      let base = core * Int(CPU_STATE_MAX)
      func ticks(_ state: Int32) -> Int {
        Int(UInt32(bitPattern: info[base + Int(state)]))
      }
      cores.append([
        ticks(CPU_STATE_USER),
        ticks(CPU_STATE_SYSTEM),
        ticks(CPU_STATE_IDLE),
        ticks(CPU_STATE_NICE),
      ])
    }

    result([
      "ticksPerSecond": sysconf(Int32(_SC_CLK_TCK)),
      "cores": cores,
    ])
  }
}
