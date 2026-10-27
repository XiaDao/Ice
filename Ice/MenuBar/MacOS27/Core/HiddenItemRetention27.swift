/// AXExtrasMenuBar can disappear while an application is concealed. Retain its
/// known items while it belongs to a hidden section, including temporary reveals.
enum HiddenItemRetention27 {
    static func retainedIDs(
        previous: [(id: UInt32, pid: Int32)],
        fresh: Set<UInt32>,
        running: Set<Int32>,
        managedHidden: Set<Int32>
    ) -> Set<UInt32> {
        Set(previous.compactMap { item in
            guard !fresh.contains(item.id), running.contains(item.pid), managedHidden.contains(item.pid) else {
                return nil
            }
            return item.id
        })
    }
}
