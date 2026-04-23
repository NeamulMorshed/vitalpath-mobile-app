import 'package:flutter_test/flutter_test.dart';
import 'package:vitalpath/providers/prescription_provider.dart';
import 'package:vitalpath/models/prescription_model.dart';
import 'package:vitalpath/models/governance_level.dart';

void main() {
  test('PrescriptionProvider starts empty', () {
    final provider = PrescriptionProvider();
    expect(provider.allPrescriptions, isEmpty);
    expect(provider.totalCount, 0);
  });

  test('PrescriptionModel builds with required fields', () {
    final now = DateTime.now();
    final rx = PrescriptionModel(
      id: 'test-001',
      patientId: 'patient-001',
      doctorName: 'Patel',
      medicineName: 'Lisinopril',
      dosage: 10.0,
      unit: DosageUnit.mg,
      startDate: now,
      endDate: now.add(const Duration(days: 30)),
      isVerified: false,
      governanceLevel: GovernanceLevel.patientManaged,
      createdAt: now,
      updatedAt: now,
    );
    expect(rx.medicineName, 'Lisinopril');
    expect(rx.dosage, 10.0);
    expect(rx.unit, DosageUnit.mg);
  });
}
