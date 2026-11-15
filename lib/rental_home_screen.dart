import 'dart:math' as math;

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _brown = Color(0xFF8A6347);
const _darkBrown = Color(0xFF5E4129);
const _panelColor = Color(0xFFEFE2D0);
const _lineColor = Color(0xFFD9C5AE);
const _green = Color(0xFF3F8F5B);
const _red = Color(0xFFC0504D);
const _orange = Color(0xFFD98A1F);
const _roomStatuses = ['ว่าง', 'มีผู้เช่า', 'จอง', 'ปิดปรับปรุง'];
const _buildings = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K'];
const _imageBucket = 'room-images';
const _maxImages = 10;

final _moneyFormat = NumberFormat('#,##0.##');
final _thaiMonths = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];
final _thaiMonthsFull = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
];

String _money(dynamic amount) =>
    '฿${_moneyFormat.format(double.tryParse('$amount') ?? 0)}';

DateTime? _dateFrom(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.length < 10) return null;
  return DateTime.tryParse(text.substring(0, 10));
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime _thaiToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 7));
  return DateTime(now.year, now.month, now.day, now.hour, now.minute);
}

String _periodFor(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

String _periodLabel(String period) {
  final parts = period.split('-');
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  return '${_thaiMonths[month - 1]} ${year + 543}';
}

String _formatThaiDate(dynamic value) {
  final date = _dateFrom(value);
  if (date == null) return '-';
  return '${date.day} ${_thaiMonths[date.month - 1]} ${date.year + 543}';
}

int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

Map<String, dynamic>? _paymentFor(
  List<Map<String, dynamic>> payments,
  dynamic roomId,
  String period,
) {
  for (final payment in payments) {
    if ('${payment['room_id']}' == '$roomId' &&
        payment['period']?.toString() == period) {
      return payment;
    }
  }
  return null;
}

class _RentMonthStatus {
  const _RentMonthStatus({
    required this.key,
    required this.due,
    required this.payment,
    required this.daysLeft,
  });

  final String key;
  final String? due;
  final Map<String, dynamic>? payment;
  final int? daysLeft;
}

_RentMonthStatus _rentMonthStatus(
  Map<String, dynamic> room,
  List<Map<String, dynamic>> payments,
  String period,
) {
  final contractDate = _dateFrom(room['contract_date']);
  final paid = _paymentFor(payments, room['id'], period);
  if (contractDate == null) {
    return _RentMonthStatus(
      key: paid == null ? 'none' : 'paid',
      due: null,
      payment: paid,
      daysLeft: null,
    );
  }
  final parts = period.split('-');
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  final dueDate = DateTime(
    year,
    month,
    math.min(contractDate.day, _daysInMonth(year, month)),
  );
  final today = _thaiToday();
  final todayOnly = DateTime(today.year, today.month, today.day);
  final difference = DateTime.utc(
    dueDate.year,
    dueDate.month,
    dueDate.day,
  ).difference(DateTime.utc(todayOnly.year, todayOnly.month, todayOnly.day));
  return _RentMonthStatus(
    key: paid != null
        ? 'paid'
        : difference.inDays < 0
        ? 'overdue'
        : 'upcoming',
    due: _dateKey(dueDate),
    payment: paid,
    daysLeft: difference.inDays,
  );
}

List<String> _periodsForRoom(Map<String, dynamic> room) {
  final contractDate = _dateFrom(room['contract_date']);
  if (contractDate == null) return [];
  final today = _thaiToday();
  final count =
      (today.year - contractDate.year) * 12 + today.month - contractDate.month;
  if (count < 0) return [];
  return List.generate(count + 1, (index) {
    final monthIndex = contractDate.year * 12 + contractDate.month - 1 + index;
    return _periodFor(DateTime(monthIndex ~/ 12, monthIndex % 12 + 1));
  });
}

class _RentSummary {
  const _RentSummary({
    required this.key,
    required this.label,
    required this.note,
    this.target,
  });

  final String key;
  final String label;
  final String note;
  final String? target;
}

_RentSummary? _rentSummary(
  Map<String, dynamic> room,
  List<Map<String, dynamic>> payments,
) {
  if (room['status'] != 'มีผู้เช่า' || room['contract_date'] == null) {
    return null;
  }
  final periods = _periodsForRoom(room);
  final overdue = periods
      .map((period) => (period, _rentMonthStatus(room, payments, period)))
      .where((entry) => entry.$2.key == 'overdue')
      .toList();
  if (overdue.isNotEmpty) {
    final oldest = overdue.first;
    final daysLate = -(oldest.$2.daysLeft ?? 0);
    return _RentSummary(
      key: 'overdue',
      label: 'เกินกำหนดชำระ',
      target: oldest.$1,
      note: overdue.length > 1
          ? 'ค้าง ${overdue.length} งวด · งวดเก่าสุดเลย $daysLate วัน'
          : 'เลยกำหนด $daysLate วัน (กำหนด ${_formatThaiDate(oldest.$2.due)})',
    );
  }
  if (periods.isEmpty) {
    return _RentSummary(
      key: 'upcoming',
      label: 'ยังไม่เริ่มสัญญา',
      note: 'เริ่ม ${_formatThaiDate(room['contract_date'])}',
    );
  }
  final current = periods.last;
  final status = _rentMonthStatus(room, payments, current);
  if (status.key == 'paid') {
    final now = _thaiToday();
    final nextMonth = DateTime(now.year, now.month + 1);
    final contractDate = _dateFrom(room['contract_date'])!;
    final nextDue = DateTime(
      nextMonth.year,
      nextMonth.month,
      math.min(contractDate.day, _daysInMonth(nextMonth.year, nextMonth.month)),
    );
    return _RentSummary(
      key: 'paid',
      label: 'จ่ายแล้ว',
      target: current,
      note: 'งวดถัดไป ${_formatThaiDate(nextDue)}',
    );
  }
  final daysLeft = status.daysLeft ?? 0;
  return _RentSummary(
    key: 'upcoming',
    label: daysLeft == 0 ? 'ครบกำหนดวันนี้' : 'ยังไม่ถึงกำหนด',
    target: current,
    note: daysLeft == 0
        ? 'กำหนด ${_formatThaiDate(status.due)}'
        : 'อีก $daysLeft วัน (กำหนด ${_formatThaiDate(status.due)})',
  );
}

class _FormImage {
  _FormImage.remote(this.url) : file = null;
  _FormImage.local(this.file) : url = null;

  final String? url;
  final XFile? file;
}

class RentalHomeScreen extends StatefulWidget {
  const RentalHomeScreen({super.key});

  @override
  State<RentalHomeScreen> createState() => _RentalHomeScreenState();
}

class _RentalHomeScreenState extends State<RentalHomeScreen> {
  SupabaseClient get _client => Supabase.instance.client;

  final _picker = ImagePicker();
  final _numberController = TextEditingController();
  final _priceController = TextEditingController();
  final _furnitureController = TextEditingController();
  final _searchController = TextEditingController();
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();

  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _payments = [];
  List<_FormImage> _formImages = [];
  String _building = '';
  String _roomStatus = 'ว่าง';
  String _filterBuilding = '';
  String _filterStatus = '';
  String _filterPayment = '';
  String _sort = 'no';
  DateTime? _contractDate;
  dynamic _editingId;
  bool _isLoading = true;
  bool _isSaving = false;
  String _loadError = '';
  String _formMessage = '';
  bool _formMessageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _numberController.dispose();
    _priceController.dispose();
    _furnitureController.dispose();
    _searchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? const Color(0xFFA03A35) : _darkBrown,
        ),
      );
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = _rooms.isEmpty;
        _loadError = '';
      });
    }
    try {
      final result = await Future.wait([
        _client.from('rooms').select(),
        _client.from('payments').select(),
      ]);
      final rooms = List<Map<String, dynamic>>.from(
        (result[0] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final payments = List<Map<String, dynamic>>.from(
        (result[1] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _payments = payments;
          _isLoading = false;
          _loadError = '';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'โหลดข้อมูลไม่สำเร็จ: $error';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredRooms {
    final minPrice = double.tryParse(_minPriceController.text);
    final maxPrice = double.tryParse(_maxPriceController.text);
    final query = _searchController.text.trim().toLowerCase();
    final rooms = _rooms.where((room) {
      final price = double.tryParse('${room['price']}') ?? 0;
      final roomNumber = '${room['room_number'] ?? ''}'.toLowerCase();
      final furniture = '${room['furniture'] ?? ''}'.toLowerCase();
      final rentSummary = _rentSummary(room, _payments);
      return (_filterBuilding.isEmpty ||
              (_filterBuilding == 'none'
                  ? room['building'] == null || room['building'] == ''
                  : room['building'] == _filterBuilding)) &&
          (minPrice == null || price >= minPrice) &&
          (maxPrice == null || price <= maxPrice) &&
          (_filterStatus.isEmpty || room['status'] == _filterStatus) &&
          (_filterPayment.isEmpty || rentSummary?.key == _filterPayment) &&
          (query.isEmpty ||
              roomNumber.contains(query) ||
              furniture.contains(query));
    }).toList();
    rooms.sort((a, b) {
      final priceA = double.tryParse('${a['price']}') ?? 0;
      final priceB = double.tryParse('${b['price']}') ?? 0;
      if (_sort == 'pa') return priceA.compareTo(priceB);
      if (_sort == 'pd') return priceB.compareTo(priceA);
      final buildingCompare = '${a['building'] ?? 'ZZ'}'.compareTo(
        '${b['building'] ?? 'ZZ'}',
      );
      if (buildingCompare != 0) return buildingCompare;
      final numberA = '${a['room_number'] ?? ''}';
      final numberB = '${b['room_number'] ?? ''}';
      final intA = int.tryParse(numberA);
      final intB = int.tryParse(numberB);
      return intA != null && intB != null
          ? intA.compareTo(intB)
          : numberA.toLowerCase().compareTo(numberB.toLowerCase());
    });
    return rooms;
  }

  @override
  Widget build(BuildContext context) {
    final email = _client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _panelColor,
        actions: [
          if (email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  email,
                  style: const TextStyle(color: Color(0xFF7A6654)),
                ),
              ),
            ),
          IconButton(
            tooltip: 'โหลดข้อมูลใหม่',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'ออกจากระบบ',
            onPressed: () async {
              try {
                await _client.auth.signOut();
              } catch (error) {
                _showMessage('ออกจากระบบไม่สำเร็จ: $error', error: true);
              }
            },
            icon: const Icon(Icons.logout, color: Color(0xFFA03A35)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1000) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: ColoredBox(
                    color: _panelColor,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _buildSidebar(email),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: _buildMainContent(),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(email),
                const SizedBox(height: 16),
                _buildMainContent(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebar(String email) {
    final free = _rooms.where((room) => room['status'] == 'ว่าง').length;
    final rented = _rooms.where((room) => room['status'] == 'มีผู้เช่า').length;
    final overdue = _rooms
        .where((room) => _rentSummary(room, _payments)?.key == 'overdue')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '🏢 ระบบจัดการห้องเช่า',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _darkBrown,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'เวลาไทย: ${_formatThaiDate(_thaiToday())} ${DateFormat('HH:mm').format(_thaiToday())}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF7A6654)),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.65,
          children: [
            _statBox('ห้องทั้งหมด', _rooms.length),
            _statBox('ว่าง', free),
            _statBox('มีผู้เช่า', rented),
            _statBox('เกินกำหนดชำระ', overdue, warning: true),
          ],
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            email,
            style: const TextStyle(fontSize: 12, color: Color(0xFF7A6654)),
          ),
        ],
        const Divider(height: 24),
        Text(
          _editingId == null ? 'เพิ่มห้องใหม่' : 'แก้ไขข้อมูลห้อง',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: _darkBrown,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: _dropdown<String>(
                label: 'ตึก / โซน *',
                value: _building.isEmpty ? null : _building,
                items: _buildings
                    .map(
                      (building) => DropdownMenuItem(
                        value: building,
                        child: Text('ตึก $building'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _building = value ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: _textField(
                label: 'เลขห้อง *',
                controller: _numberController,
                hint: 'เช่น 101',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _textField(
          label: 'ราคาต่อเดือน (บาท) *',
          controller: _priceController,
          hint: 'เช่น 4500',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 8),
        _textField(
          label: 'เฟอร์นิเจอร์',
          controller: _furnitureController,
          hint: 'เช่น เตียง, ตู้เสื้อผ้า, แอร์',
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        _dropdown<String>(
          label: 'สถานะห้อง',
          value: _roomStatus,
          items: _roomStatuses
              .map(
                (status) =>
                    DropdownMenuItem(value: status, child: Text(status)),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _roomStatus = value ?? 'ว่าง';
            });
          },
        ),
        if (_roomStatus == 'มีผู้เช่า') ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _selectContractDate,
            icon: const Icon(Icons.calendar_month),
            label: Text(
              _contractDate == null
                  ? 'เลือกวันที่ทำสัญญา *'
                  : 'ทำสัญญา ${_formatThaiDate(_contractDate)}',
            ),
          ),
          const Text(
            'ระบบใช้วันที่ทำสัญญาเป็นวันครบกำหนดชำระทุกเดือน',
            style: TextStyle(fontSize: 11, color: Color(0xFF7A6654)),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'รูปภาพ${_formImages.isEmpty ? '' : ' (${_formImages.length}/$_maxImages)'}',
            style: const TextStyle(color: Color(0xFF6B5645), fontSize: 13),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _pickFormImages,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('เลือกรูปภาพ'),
        ),
        if (_formImages.isNotEmpty) ...[
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _formImages.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final image = _formImages[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _formImage(image),
                  ),
                  if (index == 0)
                    const Positioned(
                      left: 3,
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _brown,
                          borderRadius: BorderRadius.all(Radius.circular(5)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          child: Text(
                            'หน้าปก',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: _smallImageButton(
                      icon: Icons.close,
                      onPressed: () =>
                          setState(() => _formImages.removeAt(index)),
                    ),
                  ),
                  if (index > 0)
                    Positioned(
                      left: 2,
                      top: 2,
                      child: _smallImageButton(
                        icon: Icons.star,
                        onPressed: () => setState(() {
                          final cover = _formImages.removeAt(index);
                          _formImages.insert(0, cover);
                        }),
                      ),
                    ),
                ],
              );
            },
          ),
          const Text(
            'รูปแรกเป็นรูปหน้าปก แตะดาวเพื่อเปลี่ยนหน้าปก',
            style: TextStyle(fontSize: 11, color: Color(0xFF7A6654)),
          ),
        ],
        const SizedBox(height: 8),
        if (_formMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _formMessage,
              style: TextStyle(
                color: _formMessageIsError ? const Color(0xFFA03A35) : _green,
                fontSize: 12,
              ),
            ),
          ),
        FilledButton(
          onPressed: _isSaving ? null : _saveRoom,
          style: FilledButton.styleFrom(backgroundColor: _brown),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(_editingId == null ? 'บันทึกห้อง' : 'บันทึกการแก้ไข'),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: _clearForm,
          child: const Text('ล้างฟอร์ม / ยกเลิกการแก้ไข'),
        ),
      ],
    );
  }

  Widget _statBox(String title, int value, {bool warning = false}) {
    return Container(
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFDE4E2) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: warning ? const Color(0xFFE3A8A4) : _lineColor,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: warning ? _red : _brown,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Color(0xFF7A6654)),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B5645)),
        ),
        const SizedBox(height: 3),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _lineColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _lineColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B5645)),
        ),
        const SizedBox(height: 3),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _lineColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallImageButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
      ),
    );
  }

  Widget _formImage(_FormImage image) {
    if (image.url != null) {
      return Image.network(
        image.url!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image)),
      );
    }
    return FutureBuilder(
      future: image.file!.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }

  Future<void> _selectContractDate() async {
    final today = _thaiToday();
    final date = await showDatePicker(
      context: context,
      initialDate: _contractDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 20),
      helpText: 'เลือกวันที่ทำสัญญา',
    );
    if (date != null) setState(() => _contractDate = date);
  }

  Future<List<XFile>> _selectImages() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    return files;
  }

  Future<void> _pickFormImages() async {
    try {
      final files = await _selectImages();
      if (files.isEmpty || !mounted) return;
      final space = _maxImages - _formImages.length;
      if (files.length > space) {
        _showMessage('เพิ่มรูปได้อีก $space รูป (สูงสุด $_maxImages รูป)');
      }
      setState(() {
        _formImages.addAll(
          files.take(space).map((file) => _FormImage.local(file)),
        );
      });
    } catch (error) {
      _showMessage('เลือกรูปภาพไม่สำเร็จ: $error', error: true);
    }
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _building = '';
      _roomStatus = 'ว่าง';
      _contractDate = null;
      _formImages = [];
      _formMessage = '';
      _numberController.clear();
      _priceController.clear();
      _furnitureController.clear();
    });
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('ยืนยัน'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String> _uploadImage(XFile file) async {
    final bytes = await file.readAsBytes();
    final originalName = file.name;
    final extension = originalName.contains('.')
        ? originalName.split('.').last.toLowerCase()
        : 'jpg';
    final safeExtension = RegExp(r'^[a-z0-9]{1,6}$').hasMatch(extension)
    ? extension
    : 'jpg';

    final path = '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(999999)}.$safeExtension';

    final mimeType =
        file.mimeType ?? (safeExtension == 'png' ? 'image/png' : 'image/jpeg');
    await _client.storage
        .from(_imageBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );
    return _client.storage.from(_imageBucket).getPublicUrl(path);
  }

  Future<void> _removeImage(String url) async {
    final marker = '/$_imageBucket/';
    final index = url.indexOf(marker);
    if (index < 0) return;
    final path = Uri.decodeComponent(url.substring(index + marker.length));
    await _client.storage.from(_imageBucket).remove([path]);
  }

  List<Map<String, dynamic>> _paymentsFor(dynamic roomId) => _payments
      .where((payment) => '${payment['room_id']}' == '$roomId')
      .toList();

  Future<void> _shiftPayments(dynamic roomId, int months) async {
    final records = _paymentsFor(roomId)
      ..sort((a, b) => '${a['period']}'.compareTo('${b['period']}'));
    if (months > 0) {
      for (final payment in records.reversed) {
        await _shiftPayment(payment, months);
      }
    } else {
      for (final payment in records) {
        await _shiftPayment(payment, months);
      }
    }
  }

  Future<void> _shiftPayment(Map<String, dynamic> payment, int months) async {
    final parts = '${payment['period']}'.split('-');
    final source = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final target = DateTime(source.year, source.month + months);
    await _client
        .from('payments')
        .update({'period': _periodFor(target)})
        .eq('id', payment['id']);
  }

  Future<void> _clearPayments(dynamic roomId) async {
    await _client.from('payments').delete().eq('room_id', roomId);
  }

  Future<void> _saveRoom() async {
    final building = _building;
    final number = _numberController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final status = _roomStatus;
    if (building.isEmpty ||
        number.isEmpty ||
        price == null ||
        price < 0 ||
        (status == 'มีผู้เช่า' && _contractDate == null)) {
      setState(() {
        _formMessage = status == 'มีผู้เช่า'
            ? 'กรุณาเลือกตึก กรอกเลขห้อง ราคา และวันที่ทำสัญญา'
            : 'กรุณาเลือกตึก กรอกเลขห้อง และราคาให้ถูกต้อง';
        _formMessageIsError = true;
      });
      return;
    }
    final old = _editingId == null
        ? null
        : _rooms.where((room) => '${room['id']}' == '$_editingId').firstOrNull;
    var shiftBy = 0;
    var clearOldPayments = false;
    if (old != null && status == 'มีผู้เช่า') {
      final oldPayments = _paymentsFor(old['id']);
      final wasRented =
          old['status'] == 'มีผู้เช่า' && old['contract_date'] != null;
      if (wasRented && oldPayments.isNotEmpty) {
        final previousDate = _dateFrom(old['contract_date'])!;
        shiftBy =
            (_contractDate!.year - previousDate.year) * 12 +
            _contractDate!.month -
            previousDate.month;
        if (shiftBy != 0) {
          final accepted = await _confirm(
            'เปลี่ยนวันที่ทำสัญญา',
            'ประวัติการชำระ ${oldPayments.length} งวดจะเลื่อนตามไป $shiftBy เดือน '
                '(วันที่โอนและจำนวนเงินจะไม่เปลี่ยน) ต้องการดำเนินการต่อหรือไม่?',
          );
          if (!accepted) return;
        }
      } else if (!wasRented && oldPayments.isNotEmpty) {
        clearOldPayments = await _confirm(
          'พบประวัติผู้เช่าเดิม',
          'ห้องนี้มีประวัติการชำระ ${oldPayments.length} งวด ต้องการลบประวัติเก่าและเริ่มงวดใหม่หรือไม่?',
        );
      }
    }

    setState(() {
      _isSaving = true;
      _formMessage = 'กำลังบันทึก...';
      _formMessageIsError = false;
    });
    final uploadedUrls = <String>[];
    var roomSaved = false;
    try {
      final imageUrls = <String>[];
      for (final image in _formImages) {
        if (image.file != null) {
          final url = await _uploadImage(image.file!);
          uploadedUrls.add(url);
          imageUrls.add(url);
        } else if (image.url != null) {
          imageUrls.add(image.url!);
        }
      }
      final payload = <String, dynamic>{
        'building': building,
        'room_number': number,
        'price': price,
        'status': status,
        'furniture': _furnitureController.text.trim(),
        'images': imageUrls,
        'contract_date': status == 'มีผู้เช่า'
            ? _dateKey(_contractDate!)
            : null,
        'due_day': status == 'มีผู้เช่า' ? _contractDate!.day : null,
      };
      if (_editingId == null) {
        await _client.from('rooms').insert(payload);
      } else {
        await _client.from('rooms').update(payload).eq('id', _editingId);
      }
      roomSaved = true;
      if (old != null && shiftBy != 0) {
        await _shiftPayments(old['id'], shiftBy);
      }
      if (old != null && clearOldPayments) {
        await _clearPayments(old['id']);
      }
      if (old != null) {
        final removed = (old['images'] as List? ?? [])
            .map((url) => url.toString())
            .where((url) => !imageUrls.contains(url));
        for (final url in removed) {
          await _removeImage(url);
        }
      }
      _clearForm();
      _showMessage('บันทึกข้อมูลห้องเรียบร้อย');
      await _loadData();
    } catch (error) {
      if (!roomSaved) {
        for (final url in uploadedUrls) {
          try {
            await _removeImage(url);
          } catch (cleanupError) {
            debugPrint('ลบรูปที่อัปโหลดไม่สำเร็จ: $cleanupError');
          }
        }
      }
      if (mounted) {
        setState(() {
          _formMessage = 'บันทึกไม่สำเร็จ: $error';
          _formMessageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _editRoom(Map<String, dynamic> room) {
    setState(() {
      _editingId = room['id'];
      _building = '${room['building'] ?? ''}';
      _roomStatus = '${room['status'] ?? 'ว่าง'}';
      _contractDate = _dateFrom(room['contract_date']);
      _numberController.text = '${room['room_number'] ?? ''}';
      _priceController.text = '${room['price'] ?? ''}';
      _furnitureController.text = '${room['furniture'] ?? ''}';
      _formImages = (room['images'] as List? ?? [])
          .map((url) => _FormImage.remote(url.toString()))
          .toList();
      _formMessage = '';
      _formMessageIsError = false;
    });
  }

  Future<void> _deleteRoom(Map<String, dynamic> room) async {
    final accepted = await _confirm(
      'ลบห้อง',
      'ยืนยันการลบห้อง ${room['building'] == null ? '' : 'ตึก ${room['building']} '}${room['room_number']}? ประวัติการชำระจะถูกลบด้วย',
    );
    if (!accepted) return;
    try {
      await _client.from('rooms').delete().eq('id', room['id']);
      for (final url in (room['images'] as List? ?? [])) {
        await _removeImage(url.toString());
      }
      await _loadData();
      _showMessage('ลบห้องเรียบร้อย');
    } catch (error) {
      _showMessage('ลบห้องไม่สำเร็จ: $error', error: true);
    }
  }

  Future<void> _addRoomImages(Map<String, dynamic> room) async {
    try {
      final selected = await _selectImages();
      if (selected.isEmpty) return;
      final current = (room['images'] as List? ?? [])
          .map((url) => url.toString())
          .toList();
      final space = _maxImages - current.length;
      if (space <= 0) {
        _showMessage('ห้องนี้มีรูปครบ $_maxImages รูปแล้ว', error: true);
        return;
      }
      if (selected.length > space) {
        _showMessage(
          'เพิ่มได้อีก $space รูป ระบบจะใช้รูปที่เลือกไว้ $space รูปแรก',
        );
      }
      for (final file in selected.take(space)) {
        current.add(await _uploadImage(file));
      }
      await _client
          .from('rooms')
          .update({'images': current})
          .eq('id', room['id']);
      await _loadData();
      _showMessage('เพิ่มรูปภาพเรียบร้อย');
    } catch (error) {
      _showMessage('เพิ่มรูปภาพไม่สำเร็จ: $error', error: true);
    }
  }

  Future<void> _endContract(Map<String, dynamic> room) async {
    final overdueCount = _periodsForRoom(room)
        .where(
          (period) =>
              _rentMonthStatus(room, _payments, period).key == 'overdue',
        )
        .length;
    final accepted = await _confirm(
      'สิ้นสุดสัญญา',
      'สิ้นสุดสัญญาห้อง ${room['room_number']} และเปลี่ยนสถานะเป็น "ว่าง"?'
          '${overdueCount > 0 ? '\n\nห้องนี้ยังค้างชำระ $overdueCount งวด' : ''}',
    );
    if (!accepted) return;
    final oldPayments = _paymentsFor(room['id']);
    var clearHistory = false;
    if (oldPayments.isNotEmpty) {
      clearHistory = await _confirm(
        'ประวัติการชำระ',
        'พบประวัติ ${oldPayments.length} งวด ยืนยันอีกครั้งเพื่อลบประวัติผู้เช่าเดิม หากไม่ยืนยัน ระบบจะเก็บประวัติไว้',
      );
    }
    try {
      await _client
          .from('rooms')
          .update({'status': 'ว่าง', 'contract_date': null, 'due_day': null})
          .eq('id', room['id']);
      if (clearHistory) await _clearPayments(room['id']);
      await _loadData();
      _showMessage('สิ้นสุดสัญญาเรียบร้อย');
    } catch (error) {
      _showMessage('สิ้นสุดสัญญาไม่สำเร็จ: $error', error: true);
    }
  }

  Future<void> _openRentHistory(
    Map<String, dynamic> room, {
    String? period,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _RentHistoryDialog(
        room: room,
        payments: _paymentsFor(room['id']),
        initialPeriod: period,
        onChanged: _loadData,
      ),
    );
    await _loadData();
  }

  void _openGallery(Map<String, dynamic> room) {
    final images = (room['images'] as List? ?? [])
        .map((url) => url.toString())
        .toList();
    if (images.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) => _GalleryDialog(
        room: room,
        images: images,
        summary: _rentSummary(room, _payments),
      ),
    );
  }

  Widget _buildMainContent() {
    final filtered = _filteredRooms;
    if (_isLoading && _rooms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilters(),
        const SizedBox(height: 12),
        Text(
          _loadError.isNotEmpty
              ? _loadError
              : 'พบ ${filtered.length} ห้อง จากทั้งหมด ${_rooms.length} ห้อง',
          style: TextStyle(
            color: _loadError.isNotEmpty
                ? const Color(0xFFA03A35)
                : const Color(0xFF6B5645),
          ),
        ),
        const SizedBox(height: 8),
        if (_isLoading)
          const LinearProgressIndicator()
        else if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: Text(
                'ไม่พบห้องที่ตรงกับเงื่อนไข',
                style: TextStyle(color: Color(0xFF8A7662)),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisExtent: constraints.maxWidth < 380 ? 490 : 500,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, index) =>
                    _buildRoomCard(filtered[index]),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D1),
        border: Border.all(color: const Color(0xFFE8C868), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _filterDropdown(
            label: 'ตึก / โซน',
            width: 145,
            value: _filterBuilding,
            options: [
              const DropdownMenuItem(value: '', child: Text('ทุกตึก')),
              ..._buildings.map(
                (building) => DropdownMenuItem(
                  value: building,
                  child: Text('ตึก $building'),
                ),
              ),
              const DropdownMenuItem(value: 'none', child: Text('ไม่ระบุตึก')),
            ],
            onChanged: (value) => setState(() => _filterBuilding = value ?? ''),
          ),
          _filterField(
            'ราคาต่ำสุด',
            _minPriceController,
            'เช่น 4000',
            onChanged: (_) => setState(() {}),
          ),
          _filterField(
            'ราคาสูงสุด',
            _maxPriceController,
            'เช่น 5000',
            onChanged: (_) => setState(() {}),
          ),
          _filterDropdown(
            label: 'สถานะห้อง',
            width: 155,
            value: _filterStatus,
            options: [
              const DropdownMenuItem(value: '', child: Text('ทั้งหมด')),
              ..._roomStatuses.map(
                (status) =>
                    DropdownMenuItem(value: status, child: Text(status)),
              ),
            ],
            onChanged: (value) => setState(() => _filterStatus = value ?? ''),
          ),
          _filterDropdown(
            label: 'สถานะค่าเช่า',
            width: 170,
            value: _filterPayment,
            options: const [
              DropdownMenuItem(value: '', child: Text('ทั้งหมด')),
              DropdownMenuItem(value: 'overdue', child: Text('เกินกำหนดชำระ')),
              DropdownMenuItem(
                value: 'upcoming',
                child: Text('ยังไม่ถึงกำหนด'),
              ),
              DropdownMenuItem(value: 'paid', child: Text('จ่ายแล้ว')),
            ],
            onChanged: (value) => setState(() => _filterPayment = value ?? ''),
          ),
          _filterField(
            'ค้นหาเลขห้อง / เฟอร์นิเจอร์',
            _searchController,
            'เช่น 101 หรือ แอร์',
            width: 190,
            onChanged: (_) => setState(() {}),
          ),
          _filterDropdown(
            label: 'เรียงตาม',
            width: 160,
            value: _sort,
            options: const [
              DropdownMenuItem(value: 'no', child: Text('ตึก → เลขห้อง')),
              DropdownMenuItem(value: 'pa', child: Text('ราคา ต่ำ → สูง')),
              DropdownMenuItem(value: 'pd', child: Text('ราคา สูง → ต่ำ')),
            ],
            onChanged: (value) => setState(() => _sort = value ?? 'no'),
          ),
          OutlinedButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.restart_alt),
            label: const Text('รีเซ็ต'),
          ),
        ],
      ),
    );
  }

  Widget _filterField(
    String label,
    TextEditingController controller,
    String hint, {
    double width = 145,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 3),
          TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 9,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _lineColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required double width,
    required String value,
    required List<DropdownMenuItem<String>> options,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 3),
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            items: options,
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _lineColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _filterBuilding = '';
      _filterStatus = '';
      _filterPayment = '';
      _sort = 'no';
      _searchController.clear();
      _minPriceController.clear();
      _maxPriceController.clear();
    });
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final images = (room['images'] as List? ?? [])
        .map((url) => url.toString())
        .toList();
    final status = '${room['status'] ?? 'ไม่ระบุ'}';
    final summary = _rentSummary(room, _payments);
    final rented = status == 'มีผู้เช่า';
    final statusColor = switch (status) {
      'ว่าง' => _green,
      'มีผู้เช่า' => _red,
      'จอง' => _orange,
      'ปิดปรับปรุง' => Colors.grey,
      _ => Colors.grey,
    };
    return Card(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: _lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 145,
            child: InkWell(
              onTap: () => _openGallery(room),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (images.isEmpty)
                    const ColoredBox(
                      color: Color(0xFFEADFCE),
                      child: Center(
                        child: Text(
                          'ไม่มีรูปภาพ',
                          style: TextStyle(color: Color(0xFFA38B74)),
                        ),
                      ),
                    )
                  else
                    _imageCollage(images),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _darkBrown,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        child: Text(
                          room['building'] == null || room['building'] == ''
                              ? 'ไม่ระบุตึก'
                              : 'ตึก ${room['building']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (images.isNotEmpty)
                    Positioned(
                      right: 7,
                      bottom: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            '▧ ${images.length} รูป',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ห้อง ${room['room_number'] ?? '-'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _darkBrown,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_money(room['price'])} / เดือน',
                    style: const TextStyle(
                      color: _brown,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${room['furniture'] ?? ''}'.isEmpty
                        ? '-'
                        : '${room['furniture']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B5645),
                      fontSize: 12,
                    ),
                  ),
                  if (rented && room['contract_date'] != null)
                    Text(
                      '📝 ทำสัญญา ${_formatThaiDate(room['contract_date'])}',
                      style: const TextStyle(
                        color: Color(0xFF8A7662),
                        fontSize: 11,
                      ),
                    ),
                  if (summary != null)
                    _rentSummaryBox(room, summary)
                  else if (rented)
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Text(
                        'ยังไม่ระบุวันที่ทำสัญญา',
                        style: TextStyle(
                          color: Color(0xFF8A7662),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _cardButton(
                        'แก้ไข',
                        Icons.edit_outlined,
                        () => _editRoom(room),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _cardButton(
                        'เพิ่มรูป',
                        Icons.add_photo_alternate_outlined,
                        () => _addRoomImages(room),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: _cardButton(
                        'ค่าเช่า',
                        Icons.calendar_month,
                        () => _openRentHistory(room, period: summary?.target),
                        color: const Color(0xFFE9EEF7),
                        foreground: const Color(0xFF2F4A7A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (rented)
                      Expanded(
                        child: _cardButton(
                          'สิ้นสุดสัญญา',
                          Icons.logout,
                          () => _endContract(room),
                          color: const Color(0xFFFDEBD0),
                          foreground: const Color(0xFF9A5A10),
                        ),
                      )
                    else
                      Expanded(
                        child: _cardButton(
                          'ลบ',
                          Icons.delete_outline,
                          () => _deleteRoom(room),
                          color: const Color(0xFFF7DCD9),
                          foreground: const Color(0xFFA03A35),
                        ),
                      ),
                  ],
                ),
                if (rented)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: SizedBox(
                      width: double.infinity,
                      child: _cardButton(
                        'ลบห้อง',
                        Icons.delete_outline,
                        () => _deleteRoom(room),
                        color: const Color(0xFFF7DCD9),
                        foreground: const Color(0xFFA03A35),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageCollage(List<String> images) {
    final shown = images.take(6).toList();
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        if (index >= shown.length) {
          return const ColoredBox(color: Color(0xFFEADFCE));
        }
        return Image.network(
          shown[index],
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFFEADFCE),
            child: Icon(Icons.broken_image_outlined, color: _brown),
          ),
        );
      },
    );
  }

  Widget _rentSummaryBox(Map<String, dynamic> room, _RentSummary summary) {
    final isOverdue = summary.key == 'overdue';
    final isPaid = summary.key == 'paid';
    final background = isOverdue
        ? const Color(0xFFFDE4E2)
        : isPaid
        ? const Color(0xFFE2F3E8)
        : const Color(0xFFF3ECE1);
    final foreground = isOverdue
        ? const Color(0xFFA03A35)
        : isPaid
        ? const Color(0xFF23623B)
        : const Color(0xFF6B5645);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${summary.label}\n${summary.note}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: foreground),
              ),
            ),
            if (!isPaid && summary.target != null)
              TextButton(
                onPressed: () => _openRentHistory(room, period: summary.target),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  minimumSize: const Size(40, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Colors.white,
                ),
                child: const Text(
                  'ยืนยันโอน',
                  style: TextStyle(fontSize: 10, color: _darkBrown),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardButton(
    String label,
    IconData icon,
    VoidCallback onPressed, {
    Color color = const Color(0xFFF1E4D1),
    Color foreground = _darkBrown,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _GalleryDialog extends StatefulWidget {
  const _GalleryDialog({
    required this.room,
    required this.images,
    required this.summary,
  });

  final Map<String, dynamic> room;
  final List<String> images;
  final _RentSummary? summary;

  @override
  State<_GalleryDialog> createState() => _GalleryDialogState();
}

class _GalleryDialogState extends State<_GalleryDialog> {
  int _index = 0;

  void _step(int delta) {
    setState(
      () => _index =
          (_index + delta + widget.images.length) % widget.images.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${room['building'] == null ? '' : 'ตึก ${room['building']} · '}ห้อง ${room['room_number']} · ${room['status']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Image.network(
                          widget.images[_index],
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image, size: 60),
                        ),
                      ),
                    ),
                    if (widget.images.length > 1) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton.filledTonal(
                          onPressed: () => _step(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton.filledTonal(
                          onPressed: () => _step(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) => InkWell(
                    onTap: () => setState(() => _index = index),
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: index == _index ? _brown : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        widget.images[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_money(room['price'])} / เดือน\n${room['furniture'] ?? '-'}'
                '${widget.summary == null ? '' : '\nค่าเช่า: ${widget.summary!.label} — ${widget.summary!.note}'}',
                style: const TextStyle(color: Color(0xFF6B5645)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RentHistoryDialog extends StatefulWidget {
  const _RentHistoryDialog({
    required this.room,
    required this.payments,
    required this.onChanged,
    this.initialPeriod,
  });

  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> payments;
  final String? initialPeriod;
  final Future<void> Function() onChanged;

  @override
  State<_RentHistoryDialog> createState() => _RentHistoryDialogState();
}

class _RentHistoryDialogState extends State<_RentHistoryDialog> {
  SupabaseClient get _client => Supabase.instance.client;

  late List<Map<String, dynamic>> _payments;
  late DateTime _shownMonth;
  String? _selectedPeriod;
  DateTime _paidDate = _thaiToday();
  late final TextEditingController _amountController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _payments = widget.payments.map(Map<String, dynamic>.from).toList();
    final now = _thaiToday();
    final initial = widget.initialPeriod?.split('-');
    _shownMonth = initial == null
        ? DateTime(now.year, now.month)
        : DateTime(int.parse(initial[0]), int.parse(initial[1]));
    _selectedPeriod = widget.initialPeriod;
    _amountController = TextEditingController(
      text: '${widget.room['price'] ?? 0}',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  List<String> get _historyPeriods {
    final keys = <String>{..._periodsForRoom(widget.room)};
    for (final payment in _payments) {
      keys.add('${payment['period']}');
    }
    final result = keys.toList()..sort((a, b) => b.compareTo(a));
    return result;
  }

  Future<void> _refreshPayments() async {
    final result = await _client
        .from('payments')
        .select()
        .eq('room_id', widget.room['id']);
    if (mounted) {
      setState(() {
        _payments = List<Map<String, dynamic>>.from(
          (result as List).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
      });
    }
    await widget.onChanged();
  }

  Future<void> _savePayment(String period, String paidAt, double amount) async {
    await _client.from('payments').upsert({
      'room_id': widget.room['id'],
      'period': period,
      'paid_at': paidAt,
      'amount': amount,
    }, onConflict: 'room_id,period');
    await _refreshPayments();
  }

  Future<void> _cancelPayment(String period) async {
    await _client
        .from('payments')
        .delete()
        .eq('room_id', widget.room['id'])
        .eq('period', period);
    await _refreshPayments();
  }

  Future<void> _selectPaidDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _paidDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(_thaiToday().year + 2),
      helpText: 'เลือกวันที่โอน',
    );
    if (date != null) setState(() => _paidDate = date);
  }

  Future<void> _saveSelectedPayment() async {
    final period = _selectedPeriod;
    final amount = double.tryParse(_amountController.text);
    if (period == null || amount == null || amount < 0) {
      _showDialogMessage('กรุณากรอกจำนวนเงินให้ถูกต้อง');
      return;
    }
    setState(() => _saving = true);
    try {
      await _savePayment(period, _dateKey(_paidDate), amount);
    } catch (error) {
      _showDialogMessage('บันทึกไม่สำเร็จ: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showDialogMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFA03A35),
      ),
    );
  }

  Future<void> _togglePaid(String period, bool paid) async {
    try {
      if (paid) {
        await _savePayment(
          period,
          _dateKey(_thaiToday()),
          double.tryParse('${widget.room['price']}') ?? 0,
        );
      } else {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ยกเลิกการชำระ'),
            content: Text('ยกเลิกการชำระงวด ${_periodLabel(period)}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('กลับ'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('ยกเลิกการชำระ'),
              ),
            ],
          ),
        );
        if (accepted == true) {
          await _cancelPayment(period);
        } else {
          return;
        }
      }
    } catch (error) {
      _showDialogMessage('บันทึกไม่สำเร็จ: $error');
    }
  }

  Future<void> _editPayment(String period, Map<String, dynamic> payment) async {
    var paidDate = _dateFrom(payment['paid_at']) ?? _thaiToday();
    final amountController = TextEditingController(
      text: '${payment['amount'] ?? 0}',
    );
    final result = await showDialog<(DateTime, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('แก้ไขงวด ${_periodLabel(period)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('วันที่โอน'),
                subtitle: Text(_formatThaiDate(paidDate)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: paidDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(_thaiToday().year + 2),
                  );
                  if (value != null) setLocalState(() => paidDate = value);
                },
              ),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'จำนวนเงิน (บาท)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount < 0) return;
                Navigator.pop(context, (paidDate, amount));
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    if (result == null) return;
    try {
      await _savePayment(period, _dateKey(result.$1), result.$2);
    } catch (error) {
      _showDialogMessage('บันทึกไม่สำเร็จ: $error');
    }
  }

  void _changeMonth(int offset) {
    setState(
      () =>
          _shownMonth = DateTime(_shownMonth.year, _shownMonth.month + offset),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final contractDate = _dateFrom(room['contract_date']);
    final calendarPeriods = contractDate == null
        ? <String>{}
        : _periodsForRoom(room).toSet();
    final firstWeekday =
        DateTime.utc(_shownMonth.year, _shownMonth.month, 1).weekday % 7;
    final days = _daysInMonth(_shownMonth.year, _shownMonth.month);
    final today = _thaiToday();
    final calendarCells = <Widget>[
      ...['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'].map(
        (day) => Center(
          child: Text(
            day,
            style: const TextStyle(fontSize: 12, color: Color(0xFF7A6654)),
          ),
        ),
      ),
      ...List.generate(firstWeekday, (_) => const SizedBox.shrink()),
      ...List.generate(days, (index) {
        final day = index + 1;
        final period = _periodFor(_shownMonth);
        final due = contractDate == null
            ? null
            : math.min(contractDate.day, days);
        final isDue = day == due && calendarPeriods.contains(period);
        final status = isDue ? _rentMonthStatus(room, _payments, period) : null;
        final selected = isDue && _selectedPeriod == period;
        final isToday =
            today.year == _shownMonth.year &&
            today.month == _shownMonth.month &&
            today.day == day;
        final color = status?.key == 'paid'
            ? _green
            : status?.key == 'overdue'
            ? _red
            : status?.key == 'upcoming'
            ? _orange
            : Colors.white;
        return InkWell(
          onTap: isDue
              ? () {
                  setState(() {
                    _selectedPeriod = period;
                    _amountController.text = '${room['price'] ?? 0}';
                    _paidDate = _thaiToday();
                  });
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected || isToday ? _darkBrown : _lineColor,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    color: isDue ? Colors.white : Colors.black87,
                    fontWeight: isDue || isToday
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (isDue)
                  Text(
                    status?.key == 'paid'
                        ? 'จ่ายแล้ว'
                        : status?.key == 'overdue'
                        ? 'เกินกำหนด'
                        : 'รอจ่าย',
                    style: const TextStyle(color: Colors.white, fontSize: 9),
                  ),
              ],
            ),
          ),
        );
      }),
    ];

    final totalPaid = _payments.fold<double>(
      0,
      (total, payment) =>
          total + (double.tryParse('${payment['amount']}') ?? 0),
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 850),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${room['building'] == null ? '' : 'ตึก ${room['building']} · '}ห้อง ${room['room_number']} · ค่าเช่า',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _darkBrown,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        contractDate == null
                            ? 'ห้องนี้ไม่มีวันที่ทำสัญญา (แสดงเฉพาะประวัติที่เคยบันทึกไว้)'
                            : '${_money(room['price'])} / เดือน · ทำสัญญา ${_formatThaiDate(room['contract_date'])} · ครบกำหนดทุกวันที่ ${contractDate.day}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF6B5645)),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => _changeMonth(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text(
                            '${_thaiMonthsFull[_shownMonth.month - 1]} ${_shownMonth.year + 543}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _darkBrown,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _changeMonth(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      GridView.count(
                        crossAxisCount: 7,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                        childAspectRatio: 2.2,
                        children: calendarCells,
                      ),
                      const SizedBox(height: 10),
                      _buildSelectedPeriod(),
                      const Divider(height: 28),
                      const Text(
                        'ประวัติการชำระค่าเช่า',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _darkBrown,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_historyPeriods.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              'ยังไม่มีประวัติการชำระ',
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                        )
                      else
                        ..._historyPeriods.map(_buildHistoryRow),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2F3E8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ชำระแล้ว ${_payments.length} งวด รวม ${_money(totalPaid)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF23623B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPeriod() {
    final period = _selectedPeriod;
    if (period == null) {
      return const Text(
        'กดวันที่ครบกำหนดในปฏิทิน หรือเลือกงวดจากประวัติด้านล่าง',
        style: TextStyle(color: Color(0xFF7A6654), fontSize: 13),
      );
    }
    final status = _rentMonthStatus(widget.room, _payments, period);
    final payment = status.payment;
    if (payment != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFE2F3E8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'งวด ${_periodLabel(period)} · จ่ายแล้ว ${_formatThaiDate(payment['paid_at'])} · ${_money(payment['amount'])}',
                style: const TextStyle(color: Color(0xFF23623B), fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final accepted = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('ยกเลิกการชำระ'),
                          content: Text(
                            'ยกเลิกการชำระงวด ${_periodLabel(period)}?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('กลับ'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('ยืนยัน'),
                            ),
                          ],
                        ),
                      );
                      if (accepted != true) return;
                      try {
                        await _cancelPayment(period);
                      } catch (error) {
                        _showDialogMessage('ยกเลิกไม่สำเร็จ: $error');
                      }
                    },
              child: const Text('ยกเลิกการชำระ'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'งวด ${_periodLabel(period)}${status.due == null ? '' : ' · กำหนด ${_formatThaiDate(status.due)}'}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        if (status.key == 'overdue')
          Text(
            'เกินกำหนดชำระ ${-(status.daysLeft ?? 0)} วัน',
            style: const TextStyle(color: Color(0xFFA03A35), fontSize: 14),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selectPaidDate,
                icon: const Icon(Icons.calendar_month),
                label: Text('โอน ${_formatThaiDate(_paidDate)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'จำนวนเงิน',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _saving ? null : _saveSelectedPayment,
          icon: const Icon(Icons.check),
          label: const Text('ยืนยันการโอน'),
        ),
      ],
    );
  }

  Widget _buildHistoryRow(String period) {
    final status = _rentMonthStatus(widget.room, _payments, period);
    final payment = status.payment;
    final isOverdue = payment == null && status.key == 'overdue';
    final selected = _selectedPeriod == period;

    final statusText = payment != null
        ? 'จ่ายแล้ว'
        : isOverdue
        ? 'เกินกำหนด ${-(status.daysLeft ?? 0)} วัน'
        : 'รอชำระ';
    final statusColor = payment != null
        ? _green
        : isOverdue
        ? _red
        : const Color(0xFF8A7662);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: selected ? const Color(0xFFFFF3D1) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? _brown : _lineColor,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          final parts = period.split('-');
          setState(() {
            _selectedPeriod = period;
            _shownMonth = DateTime(int.parse(parts[0]), int.parse(parts[1]));
            _amountController.text = '${widget.room['price'] ?? 0}';
            _paidDate = _thaiToday();
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Transform.scale(
                scale: 1.25,
                child: Checkbox(
                  value: payment != null,
                  onChanged: (value) => _togglePaid(period, value ?? false),
                  activeColor: _green,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _periodLabel(period),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _darkBrown,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status.due == null
                          ? 'กำหนดชำระ: -'
                          : 'กำหนดชำระ: ${_formatThaiDate(status.due)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B5645),
                      ),
                    ),
                    if (payment != null)
                      Text(
                        'โอนเมื่อ ${_formatThaiDate(payment['paid_at'])} · ${_money(payment['amount'])}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF23623B),
                        ),
                      ),
                  ],
                ),
              ),
              if (payment != null)
                IconButton(
                  tooltip: 'แก้ไขวันที่โอนหรือจำนวนเงิน',
                  onPressed: () => _editPayment(period, payment),
                  icon: const Icon(Icons.edit_outlined, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}