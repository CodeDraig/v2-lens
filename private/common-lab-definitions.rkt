#lang racket/base

(require "definition-registry.rkt")

(provide common-lab-registry)

(define (immutable-string-vector values)
  (vector->immutable-vector (list->vector values)))

(define (segment label fields)
  (segment-definition label (immutable-string-vector fields)))

;; Source: https://www.hl7.eu/HL7v2x/v251/hl7v251segmMSH.htm
(define msh-fields
  (list "Field Separator"
        "Encoding Characters"
        "Sending Application"
        "Sending Facility"
        "Receiving Application"
        "Receiving Facility"
        "Date/Time Of Message"
        "Security"
        "Message Type"
        "Message Control ID"
        "Processing ID"
        "Version ID"
        "Sequence Number"
        "Continuation Pointer"
        "Accept Acknowledgment Type"
        "Application Acknowledgment Type"
        "Country Code"
        "Character Set"
        "Principal Language Of Message"
        "Alternate Character Set Handling Scheme"
        "Message Profile Identifier"))

;; Source: https://www.hl7.eu/HL7v2x/v251/hl7v251segmPID.htm
(define pid-fields
  (list "Set ID - PID"
        "Patient ID"
        "Patient Identifier List"
        "Alternate Patient ID - PID"
        "Patient Name"
        "Mother's Maiden Name"
        "Date/Time of Birth"
        "Administrative Sex"
        "Patient Alias"
        "Race"
        "Patient Address"
        "County Code"
        "Phone Number - Home"
        "Phone Number - Business"
        "Primary Language"
        "Marital Status"
        "Religion"
        "Patient Account Number"
        "SSN Number - Patient"
        "Driver's License Number - Patient"
        "Mother's Identifier"
        "Ethnic Group"
        "Birth Place"
        "Multiple Birth Indicator"
        "Birth Order"
        "Citizenship"
        "Veterans Military Status"
        "Nationality"
        "Patient Death Date and Time"
        "Patient Death Indicator"))

;; Source: https://www.hl7.eu/HL7v2x/v251/hl7v251segmPV1.htm
(define pv1-fields
  (list "Set ID - PV1"
        "Patient Class"
        "Assigned Patient Location"
        "Admission Type"
        "Preadmit Number"
        "Prior Patient Location"
        "Attending Doctor"
        "Referring Doctor"
        "Consulting Doctor"
        "Hospital Service"
        "Temporary Location"
        "Preadmit Test Indicator"
        "Re-admission Indicator"
        "Admit Source"
        "Ambulatory Status"
        "VIP Indicator"
        "Admitting Doctor"
        "Patient Type"
        "Visit Number"
        "Financial Class"
        "Charge Price Indicator"
        "Courtesy Code"
        "Credit Rating"
        "Contract Code"
        "Contract Effective Date"
        "Contract Amount"
        "Contract Period"
        "Interest Code"
        "Transfer to Bad Debt Code"
        "Transfer to Bad Debt Date"
        "Bad Debt Agency Code"
        "Bad Debt Transfer Amount"
        "Bad Debt Recovery Amount"
        "Delete Account Indicator"
        "Delete Account Date"
        "Discharge Disposition"
        "Discharged to Location"
        "Diet Type"
        "Servicing Facility"
        "Bed Status"
        "Account Status"
        "Pending Location"
        "Prior Temporary Location"
        "Admit Date/Time"
        "Discharge Date/Time"
        "Current Patient Balance"
        "Total Charges"
        "Total Adjustments"
        "Total Payments"
        "Alternate Visit ID"
        "Visit Indicator"
        "Other Healthcare Provider"))

;; Source: https://www.hl7.eu/HL7v2x/v251/hl7v251segmORC.htm
(define orc-fields
  (list "Order Control"
        "Placer Order Number"
        "Filler Order Number"
        "Placer Group Number"
        "Order Status"
        "Response Flag"
        "Quantity/Timing"
        "Parent"
        "Date/Time of Transaction"
        "Entered By"
        "Verified By"
        "Ordering Provider"
        "Enterer's Location"
        "Call Back Phone Number"
        "Order Effective Date/Time"
        "Order Control Code Reason"
        "Entering Organization"
        "Entering Device"
        "Action By"
        "Advanced Beneficiary Notice Code"
        "Ordering Facility Name"
        "Ordering Facility Address"
        "Ordering Facility Phone Number"
        "Ordering Provider Address"
        "Order Status Modifier"
        "Advanced Beneficiary Notice Override Reason"
        "Filler's Expected Availability Date/Time"
        "Confidentiality Code"
        "Order Type"
        "Enterer Authorization Mode"))

;; Source: https://www.hl7.eu/HL7v2x/v251/hl7v251segmOBR.htm
(define obr-fields
  (list "Set ID - OBR"
        "Placer Order Number"
        "Filler Order Number"
        "Universal Service Identifier"
        "Priority - OBR"
        "Requested Date/Time"
        "Observation Date/Time"
        "Observation End Date/Time"
        "Collection Volume"
        "Collector Identifier"
        "Specimen Action Code"
        "Danger Code"
        "Relevant Clinical Information"
        "Specimen Received Date/Time"
        "Specimen Source"
        "Ordering Provider"
        "Order Callback Phone Number"
        "Placer Field 1"
        "Placer Field 2"
        "Filler Field 1"
        "Filler Field 2"
        "Results Rpt/Status Chng - Date/Time"
        "Charge to Practice"
        "Diagnostic Serv Sect ID"
        "Result Status"
        "Parent Result"
        "Quantity/Timing"
        "Result Copies To"
        "Parent"
        "Transportation Mode"
        "Reason for Study"
        "Principal Result Interpreter"
        "Assistant Result Interpreter"
        "Technician"
        "Transcriptionist"
        "Scheduled Date/Time"
        "Number of Sample Containers"
        "Transport Logistics of Collected Sample"
        "Collector's Comment"
        "Transport Arrangement Responsibility"
        "Transport Arranged"
        "Escort Required"
        "Planned Patient Transport Comment"
        "Procedure Code"
        "Procedure Code Modifier"
        "Placer Supplemental Service Information"
        "Filler Supplemental Service Information"
        "Medically Necessary Duplicate Procedure Reason"
        "Result Handling"
        "Parent Universal Service Identifier"))

;; Source: https://www.hl7.eu/HL7v2x/v251/hl7v251segmOBX.htm
(define obx-fields
  (list "Set ID - OBX"
        "Value Type"
        "Observation Identifier"
        "Observation Sub-ID"
        "Observation Value"
        "Units"
        "References Range"
        "Abnormal Flags"
        "Probability"
        "Nature of Abnormal Test"
        "Observation Result Status"
        "Effective Date of Reference Range"
        "User Defined Access Checks"
        "Date/Time of the Observation"
        "Producer's ID"
        "Responsible Observer"
        "Observation Method"
        "Equipment Instance Identifier"
        "Date/Time of the Analysis"
        "Reserved for harmonization with V2.6"))

;; Source: https://www.hl7.eu/HL7v2x/v251/hl7v251segmNTE.htm
(define nte-fields
  (list "Set ID - NTE"
        "Source of Comment"
        "Comment"
        "Comment Type"))

;; Source: https://www.hl7.eu/HL7v2x/v251/hl7v251segmSPM.htm
(define spm-fields
  (list "Set ID - SPM"
        "Specimen ID"
        "Specimen Parent IDs"
        "Specimen Type"
        "Specimen Type Modifier"
        "Specimen Additives"
        "Specimen Collection Method"
        "Specimen Source Site"
        "Specimen Source Site Modifier"
        "Specimen Collection Site"
        "Specimen Role"
        "Specimen Collection Amount"
        "Grouped Specimen Count"
        "Specimen Description"
        "Specimen Handling Code"
        "Specimen Risk Code"
        "Specimen Collection Date/Time"
        "Specimen Received Date/Time"
        "Specimen Expiration Date/Time"
        "Specimen Availability"
        "Specimen Reject Reason"
        "Specimen Quality"
        "Specimen Appropriateness"
        "Specimen Condition"
        "Specimen Current Quantity"
        "Number of Specimen Containers"
        "Container Type"
        "Container Condition"
        "Specimen Child Role"))

(define common-segments
  (hash "MSH" (segment "Message Header" msh-fields)
        "PID" (segment "Patient Identification" pid-fields)
        "PV1" (segment "Patient Visit" pv1-fields)
        "ORC" (segment "Common Order" orc-fields)
        "OBR" (segment "Observation Request" obr-fields)
        "OBX" (segment "Observation Result" obx-fields)
        "NTE" (segment "Notes and Comments" nte-fields)
        "SPM" (segment "Specimen" spm-fields)))

(define common-lab-registry
  (definition-registry
   (vector->immutable-vector
    (vector (definition-set 'common-lab #f #f common-segments)))))
