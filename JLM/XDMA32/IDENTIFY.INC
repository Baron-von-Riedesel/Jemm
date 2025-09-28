
;--- data returned by Identify Device from ATA disks
;--- it's 256 * 16-bit words.

IDENTIFY_DEVICE_DATA struct 
if 0
  struct {
    USHORT Reserved1 : 1;
    USHORT Retired3 : 1;
    USHORT ResponseIncomplete : 1;
    USHORT Retired2 : 3;
    USHORT FixedDevice : 1;
    USHORT RemovableMedia : 1;
    USHORT Retired1 : 7;
    USHORT DeviceType : 1;
  } GeneralConfiguration;
endif
  GeneralConfiguration dw ?		;0
  NumCylinders dw ?				;1
  SpecificConfiguration dw ?	;2
  NumHeads dw ?					;3
  Retired1 dw 2 dup (?);        ;4-5 
  NumSectorsPerTrack dw ?		;6
  VendorUnique1 dw 3 dup (?)	;7-9
  SerialNumber db 20 dup (?)    ;10-19
  Retired dw 2 dup (?)			;20-21
  Obsolete1 dw ?                ;22
  FirmwareRevision db 8 dup (?) ;23-26
  ModelNumber db 40 dup (?)     ;27-46
  MaximumBlockTransfer db ?     ;47
  VendorUnique2 db ?
if 0
  struct {
    USHORT FeatureSupported : 1;
    USHORT Reserved : 15;
  } TrustedComputing;
endif
  TrustedComputing dw ?         ;48 
if 0
  struct {
    UCHAR  CurrentLongPhysicalSectorAlignment : 2;
    UCHAR  ReservedByte49 : 6;
    UCHAR  DmaSupported : 1;
    UCHAR  LbaSupported : 1;
    UCHAR  IordyDisable : 1;
    UCHAR  IordySupported : 1;
    UCHAR  Reserved1 : 1;
    UCHAR  StandybyTimerSupport : 1;
    UCHAR  Reserved2 : 2;
    USHORT ReservedWord50;
  } Capabilities;
endif
  Capabilities dw ?,?	;49-50
  ObsoleteWords51 dw ?,?;51-52
if 0
  ; bit 0: ???
  ; bit 1: field 64 valid (advanced PIO modes)
  ; bit 2: field 88 valid (UDMA modes)
  USHORT TranslationFieldsValid : 3;
  USHORT Reserved3 : 5;
  USHORT FreeFallControlSensitivity : 8;
endif
  TranslationFieldsValid db ?      ;53
  FreeFallControlSensitivity db ?
  
  NumberOfCurrentCylinders dw ? ;54
  NumberOfCurrentHeads dw ? ;55
  CurrentSectorsPerTrack dw ? ;56
  CurrentSectorCapacity dd ?  ;57-58
  CurrentMultiSectorSetting db ? ;59
if 0
  UCHAR  MultiSectorSettingValid : 1;
  UCHAR  ReservedByte59 : 3;
  UCHAR  SanitizeFeatureSupported : 1;
  UCHAR  CryptoScrambleExtCommandSupported : 1;
  UCHAR  OverwriteExtCommandSupported : 1;
  UCHAR  BlockEraseExtCommandSupported : 1;
endif
  MultiSectorSettingValid equ 0
  SupportedFlags db ?
 
  UserAddressableSectors dd ? ;60-61
  ObsoleteWord62 dw ?;62
  MultiWordDMASupport db ?;63
  MultiWordDMAActive db ?;

  AdvancedPIOModes db ? ;64
  ReservedByte64 db ?;

  MinimumMWXferCycleTime dw ?;65
  RecommendedMWXferCycleTime dw ?;66
  MinimumPIOCycleTime dw ?;67
  MinimumPIOCycleTimeIORDY dw ?;68
if 0
  struct {
    USHORT ZonedCapabilities : 2;
    USHORT NonVolatileWriteCache : 1;
    USHORT ExtendedUserAddressableSectorsSupported : 1;
    USHORT DeviceEncryptsAllUserData : 1;
    USHORT ReadZeroAfterTrimSupported : 1;
    USHORT Optional28BitCommandsSupported : 1;
    USHORT IEEE1667 : 1;
    USHORT DownloadMicrocodeDmaSupported : 1;
    USHORT SetMaxSetPasswordUnlockDmaSupported : 1;
    USHORT WriteBufferDmaSupported : 1;
    USHORT ReadBufferDmaSupported : 1;
    USHORT DeviceConfigIdentifySetDmaSupported : 1;
    USHORT LPSAERCSupported : 1;
    USHORT DeterministicReadAfterTrimSupported : 1;
    USHORT CFastSpecSupported : 1;
  } AdditionalSupported;
endif
  ExtendedUserAddressableSectorsSupported equ 3
  AdditionalSupported dw ?;69
  ReservedWords70 dw 5 dup (?);70-74
if 0
  USHORT QueueDepth : 5;
  USHORT ReservedWord75 : 11;
endif
  QueueDepth dw ? ;75
if 0
  struct {
    USHORT Reserved0 : 1;
    USHORT SataGen1 : 1;
    USHORT SataGen2 : 1;
    USHORT SataGen3 : 1;
    USHORT Reserved1 : 4;
    USHORT NCQ : 1;
    USHORT HIPM : 1;
    USHORT PhyEvents : 1;
    USHORT NcqUnload : 1;
    USHORT NcqPriority : 1;
    USHORT HostAutoPS : 1;
    USHORT DeviceAutoPS : 1;
    USHORT ReadLogDMA : 1;
    USHORT Reserved2 : 1;
    USHORT CurrentSpeed : 3;
    USHORT NcqStreaming : 1;
    USHORT NcqQueueMgmt : 1;
    USHORT NcqReceiveSend : 1;
    USHORT DEVSLPtoReducedPwrState : 1;
    USHORT Reserved3 : 8;
  } SerialAtaCapabilities;
endif
  SerialAtaCapabilities dw ?,?;76-77
if 0
  struct {
    USHORT Reserved0 : 1;
    USHORT NonZeroOffsets : 1;
    USHORT DmaSetupAutoActivate : 1;
    USHORT DIPM : 1;
    USHORT InOrderData : 1;
    USHORT HardwareFeatureControl : 1;
    USHORT SoftwareSettingsPreservation : 1;
    USHORT NCQAutosense : 1;
    USHORT DEVSLP : 1;
    USHORT HybridInformation : 1;
    USHORT Reserved1 : 6;
  } SerialAtaFeaturesSupported;
endif
  SerialAtaFeaturesSupported dw ?;78
if 0
  struct {
    USHORT Reserved0 : 1;
    USHORT NonZeroOffsets : 1;
    USHORT DmaSetupAutoActivate : 1;
    USHORT DIPM : 1;
    USHORT InOrderData : 1;
    USHORT HardwareFeatureControl : 1;
    USHORT SoftwareSettingsPreservation : 1;
    USHORT DeviceAutoPS : 1;
    USHORT DEVSLP : 1;
    USHORT HybridInformation : 1;
    USHORT Reserved1 : 6;
  } SerialAtaFeaturesEnabled;
endif
  SerialAtaFeaturesEnabled dw ?;79
  MajorRevision dw ?;80
  MinorRevision dw ?;81
if 0
  struct {
    USHORT SmartCommands : 1;
    USHORT SecurityMode : 1;
    USHORT RemovableMediaFeature : 1;
    USHORT PowerManagement : 1;
    USHORT Reserved1 : 1;
    USHORT WriteCache : 1;
    USHORT LookAhead : 1;
    USHORT ReleaseInterrupt : 1;
    USHORT ServiceInterrupt : 1;
    USHORT DeviceReset : 1;
    USHORT HostProtectedArea : 1;
    USHORT Obsolete1 : 1;
    USHORT WriteBuffer : 1;
    USHORT ReadBuffer : 1;
    USHORT Nop : 1;
    USHORT Obsolete2 : 1;
    USHORT DownloadMicrocode : 1;
    USHORT DmaQueued : 1;
    USHORT Cfa : 1;
    USHORT AdvancedPm : 1;
    USHORT Msn : 1;
    USHORT PowerUpInStandby : 1;
    USHORT ManualPowerUp : 1;
    USHORT Reserved2 : 1;
    USHORT SetMax : 1;
    USHORT Acoustics : 1;
    USHORT BigLba : 1;
    USHORT DeviceConfigOverlay : 1;
    USHORT FlushCache : 1;
    USHORT FlushCacheExt : 1;
    USHORT WordValid83 : 2;
    USHORT SmartErrorLog : 1;
    USHORT SmartSelfTest : 1;
    USHORT MediaSerialNumber : 1;
    USHORT MediaCardPassThrough : 1;
    USHORT StreamingFeature : 1;
    USHORT GpLogging : 1;
    USHORT WriteFua : 1;
    USHORT WriteQueuedFua : 1;
    USHORT WWN64Bit : 1;
    USHORT URGReadStream : 1;
    USHORT URGWriteStream : 1;
    USHORT ReservedForTechReport : 2;
    USHORT IdleWithUnloadFeature : 1;
    USHORT WordValid : 2;
  } CommandSetSupport;
endif
  CommandSetSupport dw ?,?,?;82-84
if 0
  struct {
    USHORT SmartCommands : 1;
    USHORT SecurityMode : 1;
    USHORT RemovableMediaFeature : 1;
    USHORT PowerManagement : 1;
    USHORT Reserved1 : 1;
    USHORT WriteCache : 1;
    USHORT LookAhead : 1;
    USHORT ReleaseInterrupt : 1;
    USHORT ServiceInterrupt : 1;
    USHORT DeviceReset : 1;
    USHORT HostProtectedArea : 1;
    USHORT Obsolete1 : 1;
    USHORT WriteBuffer : 1;
    USHORT ReadBuffer : 1;
    USHORT Nop : 1;
    USHORT Obsolete2 : 1;
    USHORT DownloadMicrocode : 1;
    USHORT DmaQueued : 1;
    USHORT Cfa : 1;
    USHORT AdvancedPm : 1;
    USHORT Msn : 1;
    USHORT PowerUpInStandby : 1;
    USHORT ManualPowerUp : 1;
    USHORT Reserved2 : 1;
    USHORT SetMax : 1;
    USHORT Acoustics : 1;
    USHORT BigLba : 1;
    USHORT DeviceConfigOverlay : 1;
    USHORT FlushCache : 1;
    USHORT FlushCacheExt : 1;
    USHORT Resrved3 : 1;
    USHORT Words119_120Valid : 1;
    USHORT SmartErrorLog : 1;
    USHORT SmartSelfTest : 1;
    USHORT MediaSerialNumber : 1;
    USHORT MediaCardPassThrough : 1;
    USHORT StreamingFeature : 1;
    USHORT GpLogging : 1;
    USHORT WriteFua : 1;
    USHORT WriteQueuedFua : 1;
    USHORT WWN64Bit : 1;
    USHORT URGReadStream : 1;
    USHORT URGWriteStream : 1;
    USHORT ReservedForTechReport : 2;
    USHORT IdleWithUnloadFeature : 1;
    USHORT Reserved4 : 2;
  } CommandSetActive;
endif
  CommandSetActive dw ?,?,?; 85-87
  UltraDMASupport db ?; 88
  UltraDMAActive db ?;
if 0
  struct {
    USHORT TimeRequired : 15;
    USHORT ExtendedTimeReported : 1;
  } NormalSecurityEraseUnit;
endif
  NormalSecurityEraseUnit dw ?;89
if 0
  struct {
    USHORT TimeRequired : 15;
    USHORT ExtendedTimeReported : 1;
  } EnhancedSecurityEraseUnit;
endif
  EnhancedSecurityEraseUnit dw ?;90
  CurrentAPMLevel db ?; 91
  ReservedWord91 db ?
  MasterPasswordID dw ?;92
  HardwareResetResult dw ?;93
  CurrentAcousticValue db ?;94
  RecommendedAcousticValue db ?
  StreamMinRequestSize dw ?	;95
  StreamingTransferTimeDMA dw ?;96
  StreamingAccessLatencyDMAPIO dw ?;97
  StreamingPerfGranularity dd ?;98-99
  Max48BitLBA dd ?,?	;100-103
  StreamingTransferTime dw ?;104
  DsmCap dw ?;105
if 0
  struct {
    USHORT LogicalSectorsPerPhysicalSector : 4;
    USHORT Reserved0 : 8;
    USHORT LogicalSectorLongerThan256Words : 1;
    USHORT MultipleLogicalSectorsPerPhysicalSector : 1;
    USHORT Reserved1 : 2;
  } PhysicalLogicalSectorSize;
endif
  PhysicalLogicalSectorSize dw ? ;106
  InterSeekDelay dw ?;107
  WorldWideName dw 4 dup (?);108-111
  ReservedForWorldWideName128 dw 4 dup (?);112-115
  ReservedForTlcTechnicalReport dw ?;116
  WordsPerLogicalSector dw 2 dup (?);117-118
if 0
  struct {
    USHORT ReservedForDrqTechnicalReport : 1;
    USHORT WriteReadVerify : 1;
    USHORT WriteUncorrectableExt : 1;
    USHORT ReadWriteLogDmaExt : 1;
    USHORT DownloadMicrocodeMode3 : 1;
    USHORT FreefallControl : 1;
    USHORT SenseDataReporting : 1;
    USHORT ExtendedPowerConditions : 1;
    USHORT Reserved0 : 6;
    USHORT WordValid : 2;
  } CommandSetSupportExt;
endif
  CommandSetSupportExt dw ?;119
if 0
  struct {
    USHORT ReservedForDrqTechnicalReport : 1;
    USHORT WriteReadVerify : 1;
    USHORT WriteUncorrectableExt : 1;
    USHORT ReadWriteLogDmaExt : 1;
    USHORT DownloadMicrocodeMode3 : 1;
    USHORT FreefallControl : 1;
    USHORT SenseDataReporting : 1;
    USHORT ExtendedPowerConditions : 1;
    USHORT Reserved0 : 6;
    USHORT Reserved1 : 2;
  } CommandSetActiveExt;
endif
  CommandSetActiveExt dw ?;120
  ReservedForExpandedSupportandActive dw 6 dup (?);121-126
if 0
  USHORT MsnSupport : 2;
  USHORT ReservedWord127 : 14;
endif
  MsnSupport dw ?;127
if 0
  struct {
    USHORT SecuritySupported : 1;
    USHORT SecurityEnabled : 1;
    USHORT SecurityLocked : 1;
    USHORT SecurityFrozen : 1;
    USHORT SecurityCountExpired : 1;
    USHORT EnhancedSecurityEraseSupported : 1;
    USHORT Reserved0 : 2;
    USHORT SecurityLevel : 1;
    USHORT Reserved1 : 7;
  } SecurityStatus;
endif
  SecurityStatus dw ?;128
  ReservedWord129 dw 31 dup (?);129-159
if 0
  struct {
    USHORT MaximumCurrentInMA : 12;
    USHORT CfaPowerMode1Disabled : 1;
    USHORT CfaPowerMode1Required : 1;
    USHORT Reserved0 : 1;
    USHORT Word160Supported : 1;
  } CfaPowerMode1;
endif
  CfaPowerMode1 dw ?;160
  ReservedForCfaWord161 dw 7 dup (?);161-167
if 0
  USHORT NominalFormFactor : 4;
  USHORT ReservedWord168 : 12;
endif  
  NominalFormFactor dw ?;168
if 0
  struct {
    USHORT SupportsTrim : 1;
    USHORT Reserved0 : 15;
  } DataSetManagementFeature;
endif  
  DataSetManagementFeature dw ?;169
  AdditionalProductID dw 4 dup (?);170-173
  ReservedForCfaWord174 dw 2 dup (?);174-175
  CurrentMediaSerialNumber dw 30 dup (?);176-205
if 0
  struct {
    USHORT Supported : 1;
    USHORT Reserved0 : 1;
    USHORT WriteSameSuported : 1;
    USHORT ErrorRecoveryControlSupported : 1;
    USHORT FeatureControlSuported : 1;
    USHORT DataTablesSuported : 1;
    USHORT Reserved1 : 6;
    USHORT VendorSpecific : 4;
  } SCTCommandTransport;
endif
  SCTCommandTransport dw ?;206
  ReservedWord207 dw 2 dup (?);207-208
if 0
  struct {
    USHORT AlignmentOfLogicalWithinPhysical : 14;
    USHORT Word209Supported : 1;
    USHORT Reserved0 : 1;
  } BlockAlignment;
endif  
  BlockAlignment dw ?;209
  WriteReadVerifySectorCountMode3Only dw 2 dup (?);210-211
  WriteReadVerifySectorCountMode2Only dw 2 dup (?);212-213
if 0
  struct {
    USHORT NVCachePowerModeEnabled : 1;
    USHORT Reserved0 : 3;
    USHORT NVCacheFeatureSetEnabled : 1;
    USHORT Reserved1 : 3;
    USHORT NVCachePowerModeVersion : 4;
    USHORT NVCacheFeatureSetVersion : 4;
  } NVCacheCapabilities;
endif  
  NVCacheCapabilities dw ?;214
  NVCacheSizeLSW dw ?;215
  NVCacheSizeMSW dw ?;216
  NominalMediaRotationRate dw ?;217
  ReservedWord218 dw ?;218
if 0
  struct {
    UCHAR NVCacheEstimatedTimeToSpinUpInSeconds;
    UCHAR Reserved;
  } NVCacheOptions;
endif
  NVCacheEstimatedTimeToSpinUpInSeconds db ? ;219
  db ?
  WriteReadVerifySectorCountMode db ? ;220
  db ?
  ReservedWord221 dw ?;221
if 0
  struct {
    USHORT MajorVersion : 12;
    USHORT TransportType : 4;
  } TransportMajorVersion;
endif  
  TransportMajorVersion dw ?;222
  TransportMinorVersion dw ?;223
  ReservedWord224 dw 6 dup (?);224-229
  ExtendedNumberOfUserAddressableSectors dq ?;230-233
  MinBlocksPerDownloadMicrocodeMode03 dw ?;234
  MaxBlocksPerDownloadMicrocodeMode03 dw ?;235
  ReservedWord236 dw 19 dup (?);236-254
  Signature db ?;255
  CheckSum db ?
IDENTIFY_DEVICE_DATA ends
