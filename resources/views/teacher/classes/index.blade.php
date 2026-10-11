@extends('layouts.teacher')

@section('header', 'Classes')

@section('content')
<p class="text-sm text-slate-500 mb-4">{{ $classes->count() }} class(es)</p>

<div class="bg-white rounded-xl shadow-sm border overflow-hidden">
    <div class="overflow-x-auto">
        <table class="min-w-full text-sm">
            <thead class="bg-slate-50 text-left">
                <tr>
                    <th class="p-3">Class</th>
                    <th class="p-3 hidden md:table-cell">Subject</th>
                    <th class="p-3 hidden lg:table-cell">Grade</th>
                    <th class="p-3">Students</th>
                    <th class="p-3">Actions</th>
                </tr>
            </thead>
            <tbody>
                @forelse($classes as $class)
                <tr class="border-t">
                    <td class="p-3 font-medium">{{ $class->display_name }}</td>
                    <td class="p-3 hidden md:table-cell">{{ $class->subject?->name }}</td>
                    <td class="p-3 hidden lg:table-cell">{{ $class->grade_level }}</td>
                    <td class="p-3">{{ $class->students_count }}</td>
                    <td class="p-3 flex flex-wrap gap-3">
                        <a href="{{ route('teacher.classes.show', $class) }}" class="text-indigo-600">Manage</a>
                    </td>
                </tr>
                @empty
                <tr>
                    <td colspan="5" class="p-6 text-center text-slate-500">No classes yet.</td>
                </tr>
                @endforelse
            </tbody>
        </table>
    </div>
</div>
@endsection
