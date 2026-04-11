package elassandra.debug;

import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;

/**
 * javaagent: logs exit status and stack when {@link System#exit(int)} runs.
 * Works when {@code tests.security.manager=false} (no SecurityManager.checkExit).
 * <p>
 * Build: {@code ./scripts/build-exit-trace-javaagent.sh} → {@code /tmp/elassandra-system-exit-trace-agent.jar} (not committed).
 * Run (side-car): {@code ELASSANDRA_OPENSEARCH_TEST_EXTRA_JVM_ARGS='-javaagent:/tmp/elassandra-system-exit-trace-agent.jar' ...}
 */
public final class ExitTraceAgent {

    private ExitTraceAgent() {}

    public static void premain(String agentArgs, Instrumentation inst) {
        ClassFileTransformer transformer =
            new ClassFileTransformer() {
                @Override
                public byte[] transform(
                    ClassLoader loader,
                    String className,
                    Class<?> classBeingRedefined,
                    ProtectionDomain protectionDomain,
                    byte[] classfileBuffer) {
                    if (!"java/lang/System".equals(className)) {
                        return null;
                    }
                    ClassReader cr = new ClassReader(classfileBuffer);
                    ClassWriter cw = new ClassWriter(cr, ClassWriter.COMPUTE_MAXS | ClassWriter.COMPUTE_FRAMES);
                    ClassVisitor cv =
                        new ClassVisitor(Opcodes.ASM9, cw) {
                            @Override
                            public MethodVisitor visitMethod(
                                int access, String name, String descriptor, String signature, String[] exceptions) {
                                MethodVisitor mv = super.visitMethod(access, name, descriptor, signature, exceptions);
                                if ("exit".equals(name) && "(I)V".equals(descriptor)) {
                                    return new MethodVisitor(Opcodes.ASM9, mv) {
                                        @Override
                                        public void visitCode() {
                                            // java.base only — avoids JPMS issues calling agent classes from System
                                            mv.visitFieldInsn(Opcodes.GETSTATIC, "java/lang/System", "err", "Ljava/io/PrintStream;");
                                            mv.visitVarInsn(Opcodes.ILOAD, 0);
                                            mv.visitMethodInsn(
                                                Opcodes.INVOKEVIRTUAL,
                                                "java/io/PrintStream",
                                                "println",
                                                "(I)V",
                                                false);
                                            mv.visitMethodInsn(Opcodes.INVOKESTATIC, "java/lang/Thread", "dumpStack", "()V", false);
                                            super.visitCode();
                                        }
                                    };
                                }
                                return mv;
                            }
                        };
                    cr.accept(cv, ClassReader.EXPAND_FRAMES);
                    return cw.toByteArray();
                }
            };
        inst.addTransformer(transformer, true);
        try {
            Class<?> sys = Class.forName("java.lang.System");
            inst.retransformClasses(sys);
            System.err.println("[elassandra.exit.trace] javaagent: retransformed java.lang.System#exit — stderr will show code + stack on System.exit");
        } catch (Throwable t) {
            System.err.println("[elassandra.exit.trace] javaagent: failed to retransform java.lang.System (exit tracing inactive)");
            t.printStackTrace(System.err);
        }
    }
}
