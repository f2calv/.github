---
description: 'Azure Table Storage entity column, constructor, partition-key and table-versioning conventions.'
applyTo: '**/*Entity*.cs'
---

# Azure Table Storage

- **Column naming**: For high-volume line-item/reading entities where many thousands of rows are retrieved, use ultra-short column names (even single letters) to reduce payload size and improve retrieval speed. This optimization is not needed for low-volume snapshot/summary entities where readability is more important.
- **Expanded accessor properties**: High-volume `ITableEntity` reading entities with ultra-short column names must also expose full-name expression-bodied read-only accessor properties decorated with `[IgnoreDataMember]` for developer ergonomics (e.g. `public string IpAddress => ip;`). This provides readable access without adding storage overhead.
- **ReadingEntity constructors**: Reading entity constructors must accept the domain event record directly (e.g. `SensorReadingEntity(SensorEvent evt)`) — never individual properties unpacked at the call site. The constructor is responsible for mapping event properties to ultra-short column fields.
- **SnapshotEntity constructors**: When a snapshot entity's `RowKey` is always derivable from a property on the event (e.g. `DeviceId`, `NodeName`), the constructor should accept `(string partitionKey, TEvent evt)` and derive `RowKey` internally. Only pass `RowKey` as a separate parameter when it is a constant not present on the event (e.g. `"latest"` for single-device tables).
- **Entity-scoped PartitionKey**: When a reading entity stores data from multiple devices or sensors, `PartitionKey` should be the device/entity identifier (`DeviceId`, `NodeName`, `CameraId`, `DatapointId`, etc.) rather than a date string. Date-based PK (`yyMMdd`) is acceptable only for single-device-per-table scenarios.
- **Table name versioning**: When changing the `PartitionKey` or `RowKey` structure of an Azure Table entity, increment the table name version suffix (e.g. `readingsv1` → `readingsv2`). Old data under the previous key structure is orphaned by design — treat structural changes as fresh-start migrations.
