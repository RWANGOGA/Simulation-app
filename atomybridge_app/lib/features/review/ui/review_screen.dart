import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/api_client.dart';

class ReviewScreen extends StatefulWidget {
  final String region;
  final String painType;
  final int severity;
  final String direction;
  final String depth;
  final double heartRate;
  final double spo2;

  const ReviewScreen({
    super.key,
    required this.region,
    required this.painType,
    required this.severity,
    required this.direction,
    required this.depth,
    required this.heartRate,
    required this.spo2,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _isSubmitting = false;

  Future<void> _submitToDoctor() async {
    HapticFeedback.heavyImpact();
    setState(() => _isSubmitting = true);

    try {
      // This is where the magic happens: sending ALL data to the backend!
      final result = await ApiClient.sendTriage(TriageReport(
        bodyRegion: widget.region,
        painType: widget.painType.toLowerCase(),
        severity: widget.severity,
        direction: widget.direction,
        depth: widget.depth,
        heartRate: widget.heartRate,
      ));

      if (!mounted) return;
      _showSuccessDialog(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Error: $e'),
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog(TriageResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              result.riskScore >= 0.7 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: result.riskScore >= 0.7 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
              size: 28,
            ),
            const SizedBox(width: 10),
            const Text('Triage Summary'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (result.riskScore >= 0.7 ? const Color(0xFFDC2626) : const Color(0xFF16A34A)).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text('Risk Status: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    result.riskLevel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: result.riskScore >= 0.7 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('• Location: ${widget.region}'),
            Text('• Pain Type: ${widget.painType}'),
            Text('• Intensity: ${widget.severity} / 10'),
            Text('• Direction: ${widget.direction}'),
            Text('• Depth: ${widget.depth}'),
            Text('• Heart Rate: ${widget.heartRate.toInt()} BPM'),
            Text('• SpO2: ${widget.spo2.toInt()}%'),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).popUntil((route) => route.isFirst); // Go back to Welcome Screen
            },
            child: const Text('Return to Home', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '5. Review & Submit',
          style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clinical Summary',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 16),
                  
                  // Summary Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryRow('Location', widget.region, Icons.location_on),
                        const Divider(height: 24),
                        _buildSummaryRow('Pain Type', widget.painType, Icons.sick),
                        const Divider(height: 24),
                        _buildSummaryRow('Intensity', '${widget.severity} / 10', Icons.straighten),
                        const Divider(height: 24),
                        _buildSummaryRow('Direction', widget.direction, Icons.arrow_right_alt),
                        const Divider(height: 24),
                        _buildSummaryRow('Depth', widget.depth, Icons.layers),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(child: _buildVitalMiniCard('Heart Rate', '${widget.heartRate.toInt()} BPM', Icons.favorite, const Color(0xFF6D28D9))),
                            const SizedBox(width: 12),
                            Expanded(child: _buildVitalMiniCard('SpO2', '${widget.spo2.toInt()}%', Icons.air, Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'By submitting, you consent to sharing this clinical data with the attending physician for triage purposes.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
          
          // Submit Button
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitToDoctor,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    elevation: 3,
                    shadowColor: const Color(0xFF6D28D9).withOpacity(0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Submit to Doctor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            SizedBox(width: 8),
                            Icon(Icons.send, color: Colors.white, size: 20),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF6D28D9).withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFF6D28D9), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVitalMiniCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8), fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}