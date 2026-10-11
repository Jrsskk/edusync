import { Head, Link } from '@inertiajs/react';
import TeacherLayout from '@/Layouts/TeacherLayout';

export default function Index({ classes }) {
    return (
        <TeacherLayout title="Classes">
            <Head title="Classes" />

            <div className="mb-6">
                <div>
                    <p className="font-semibold text-slate-900">Your teaching load</p>
                    <p className="text-sm text-slate-500">{classes.length} {classes.length === 1 ? 'class' : 'classes'} this academic year</p>
                </div>
            </div>

            <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
                {classes.map((c) => (
                    <Link key={c.id} href={`/teacher/classes/${c.id}`} className="portal-card group p-5 hover:-translate-y-0.5 hover:border-emerald-300">
                        <h3 className="font-semibold">{c.name} - {c.section}</h3>
                        <p className="text-sm text-slate-500 mt-1">{c.subject?.name}</p>
                        {c.class_code && (
                            <p className="mt-2 inline-block font-mono text-xs font-bold tracking-widest text-emerald-700 bg-emerald-50 px-2 py-1 rounded">
                                {c.class_code}
                            </p>
                        )}
                        <div className="mt-4 flex flex-wrap gap-x-4 gap-y-2 border-t border-slate-100 pt-3 text-xs text-slate-600">
                            <span>{c.students_count} students</span>
                            <span>{c.quizzes_count} quizzes</span>
                            <span>{c.assignments_count} assignments</span>
                        </div>
                    </Link>
                ))}
            </div>
        </TeacherLayout>
    );
}
